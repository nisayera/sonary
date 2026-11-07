import Foundation

public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Share of busy ticks between two readings, 0...1. Never NaN.
public func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double {
    func delta(_ now: UInt64, _ before: UInt64) -> UInt64 { now >= before ? now - before : 0 }
    let busy = delta(current.user, previous.user)
        + delta(current.system, previous.system)
        + delta(current.nice, previous.nice)
    let total = busy + delta(current.idle, previous.idle)
    guard total > 0 else { return 0 }
    return min(1, Double(busy) / Double(total))
}

/// Converts a raw `integer_t` tick counter (a 32-bit value that wraps) to an unsigned count.
func tickCount(_ raw: Int32) -> UInt64 { UInt64(UInt32(bitPattern: raw)) }

public struct NetworkCounters: Sendable, Equatable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public struct NetworkRates: Sendable, Equatable {
    public var bytesInPerSec: Double
    public var bytesOutPerSec: Double

    public init(bytesInPerSec: Double, bytesOutPerSec: Double) {
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
    }

    public static let zero = NetworkRates(bytesInPerSec: 0, bytesOutPerSec: 0)
}

/// Bytes per second between two counter readings. Counter resets and a zero interval yield 0, never negatives.
public func networkRates(previous: NetworkCounters, current: NetworkCounters, interval: TimeInterval) -> NetworkRates {
    guard interval > 0 else { return .zero }
    func delta(_ now: UInt64, _ before: UInt64) -> Double { now >= before ? Double(now - before) : 0 }
    return NetworkRates(
        bytesInPerSec: delta(current.bytesIn, previous.bytesIn) / interval,
        bytesOutPerSec: delta(current.bytesOut, previous.bytesOut) / interval
    )
}

/// The load of each core between two readings, 0...1 per core. Empty when the core count
/// changed in between.
public func perCoreUsage(previous: [CPUTicks], current: [CPUTicks]) -> [Double] {
    guard previous.count == current.count else { return [] }
    return zip(previous, current).map { cpuUsage(previous: $0, current: $1) }
}

public struct DiskCounters: Sendable, Equatable {
    public var bytesRead: UInt64
    public var bytesWritten: UInt64

    public init(bytesRead: UInt64, bytesWritten: UInt64) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
    }
}

public struct DiskRates: Sendable, Equatable {
    public var readPerSec: Double
    public var writePerSec: Double

    public init(readPerSec: Double, writePerSec: Double) {
        self.readPerSec = readPerSec
        self.writePerSec = writePerSec
    }

    public static let zero = DiskRates(readPerSec: 0, writePerSec: 0)
}

/// Bytes read and written per second between two readings; resets yield 0.
public func diskRates(previous: DiskCounters, current: DiskCounters, interval: TimeInterval) -> DiskRates {
    guard interval > 0 else { return .zero }
    func delta(_ now: UInt64, _ before: UInt64) -> Double { now >= before ? Double(now - before) : 0 }
    return DiskRates(readPerSec: delta(current.bytesRead, previous.bytesRead) / interval,
                     writePerSec: delta(current.bytesWritten, previous.bytesWritten) / interval)
}

/// Cycle count, health and power draw from the battery's own registry entry
/// (AppleSmartBattery). Health is the full charge now against the design capacity; the
/// draw is positive while charging and negative on battery. Missing values stay nil.
public func batteryDetails(_ properties: [String: Any]) -> (cycles: Int?, health: Double?, watts: Double?) {
    let cycles = (properties["CycleCount"] as? NSNumber)?.intValue
    var health: Double?
    if let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue, design > 0,
       let full = ((properties["AppleRawMaxCapacity"] ?? properties["NominalChargeCapacity"]) as? NSNumber)?.doubleValue,
       full > 0 {
        health = min(1, full / design)
    }
    var watts: Double?
    if let millivolts = (properties["Voltage"] as? NSNumber)?.doubleValue,
       let milliamps = ((properties["InstantAmperage"] ?? properties["Amperage"]) as? NSNumber)?.int64Value {
        watts = millivolts * Double(milliamps) / 1_000_000
    }
    return (cycles, health, watts)
}

/// A USB device that is plugged in.
public struct USBDevice: Sendable, Equatable, Identifiable {
    public var name: String
    public var vendor: String?
    public var id: String

    public init(name: String, vendor: String?, id: String) {
        self.name = name
        self.vendor = vendor
        self.id = id
    }
}

/// Turns IOKit USB device properties into named devices, without the hubs and the Mac's
/// own internal parts that have no name.
public func parseUSBDevices(_ services: [[String: Any]]) -> [USBDevice] {
    var seen = Set<String>()
    return services.compactMap { service in
        let name = (service["USB Product Name"] as? String) ?? (service["kUSBProductString"] as? String)
        guard let name, !name.isEmpty, !name.localizedCaseInsensitiveContains("hub") else { return nil }
        let vendor = (service["USB Vendor Name"] as? String) ?? (service["kUSBVendorString"] as? String)
        let location = (service["locationID"] as? NSNumber)?.stringValue ?? name
        guard seen.insert(location).inserted else { return nil }
        return USBDevice(name: name, vendor: vendor, id: location)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// Power figures from the battery's registry entry, the charger's details and the SMC's
/// power sensors. Battery temperature comes in hundredths of a degree, voltage in mV and
/// current in mA. Nil fields stay nil; nothing is guessed.
public func powerStats(battery: [String: Any], adapter: [String: Any], systemWatts: Double?,
                       adapterInputWatts: Double?) -> PowerStats {
    func number(_ key: String) -> Double? { (battery[key] as? NSNumber)?.doubleValue }
    let millivolts = number("Voltage")
    let milliamps = ((battery["InstantAmperage"] ?? battery["Amperage"]) as? NSNumber).map { Double($0.int64Value) }
    var batteryWatts: Double?
    if let millivolts, let milliamps { batteryWatts = millivolts * milliamps / 1_000_000 }
    let rated = (adapter["Watts"] as? NSNumber)?.doubleValue
    let name = (adapter["Name"] as? String) ?? (adapter["Description"] as? String)
    func positive(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 > 0.05 ? $0 : nil } }
    return PowerStats(
        systemWatts: positive(systemWatts),
        adapterWatts: positive(adapterInputWatts),
        adapterRatedWatts: positive(rated),
        adapterName: name.flatMap { $0.isEmpty ? nil : $0 },
        batteryWatts: batteryWatts,
        voltage: millivolts.map { $0 / 1000 },
        amperage: milliamps.map { $0 / 1000 },
        batteryTemperature: number("Temperature").map { $0 / 100 },
        designCapacity: (battery["DesignCapacity"] as? NSNumber)?.intValue,
        fullCapacity: ((battery["AppleRawMaxCapacity"] ?? battery["NominalChargeCapacity"]) as? NSNumber)?.intValue,
        currentCapacity: (battery["AppleRawCurrentCapacity"] as? NSNumber)?.intValue,
        isPluggedIn: (battery["ExternalConnected"] as? Bool) ?? !adapter.isEmpty,
        isFullyCharged: (battery["FullyCharged"] as? Bool) ?? false
    )
}

/// Watts as the panel writes them: "18.4 W", or "0.6 W" for small values.
public func formatWatts(_ watts: Double) -> String {
    String(format: abs(watts) >= 100 ? "%.0f W" : "%.1f W", watts)
}

/// A temperature in the unit the user picked.
public func formatTemperature(_ celsius: Double, fahrenheit: Bool) -> String {
    fahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded())) °F" : "\(Int(celsius.rounded())) °C"
}
