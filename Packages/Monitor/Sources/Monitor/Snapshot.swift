import Foundation

public struct MemoryStats: Sendable, Equatable {
    public enum Pressure: Sendable, Equatable { case normal, warning, critical }

    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var pressure: Pressure

    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: Pressure) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
    }

    public var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }
}

public struct DiskStats: Sendable, Equatable {
    public var freeBytes: UInt64
    public var totalBytes: UInt64

    public init(freeBytes: UInt64, totalBytes: UInt64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }

    public var freeFraction: Double {
        totalBytes > 0 ? min(1, Double(freeBytes) / Double(totalBytes)) : 0
    }
}

public struct BatteryStats: Sendable, Equatable {
    public var level: Double
    public var isCharging: Bool
    public var watts: Double?
    public var minutesRemaining: Int?
    public var cycleCount: Int?
    /// Full charge now against the design capacity, 0...1.
    public var health: Double?

    public init(level: Double, isCharging: Bool, watts: Double? = nil, minutesRemaining: Int? = nil,
                cycleCount: Int? = nil, health: Double? = nil) {
        self.level = level
        self.isCharging = isCharging
        self.watts = watts
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.health = health
    }
}

/// Where the power goes: what the whole Mac draws, what comes in from the charger, and the
/// battery's side of it, plus the battery's own measurements.
public struct PowerStats: Sendable, Equatable {
    /// The whole Mac, in watts.
    public var systemWatts: Double?
    /// What arrives from the charger, in watts.
    public var adapterWatts: Double?
    /// What the charger is rated for, in watts.
    public var adapterRatedWatts: Double?
    public var adapterName: String?
    /// Positive while charging, negative on battery.
    public var batteryWatts: Double?
    public var voltage: Double?
    public var amperage: Double?
    /// The battery's temperature in °C.
    public var batteryTemperature: Double?
    /// Capacities in mAh.
    public var designCapacity: Int?
    public var fullCapacity: Int?
    public var currentCapacity: Int?
    public var isPluggedIn: Bool
    public var isFullyCharged: Bool

    public init(systemWatts: Double? = nil, adapterWatts: Double? = nil, adapterRatedWatts: Double? = nil,
                adapterName: String? = nil, batteryWatts: Double? = nil, voltage: Double? = nil, amperage: Double? = nil,
                batteryTemperature: Double? = nil, designCapacity: Int? = nil, fullCapacity: Int? = nil,
                currentCapacity: Int? = nil, isPluggedIn: Bool = false, isFullyCharged: Bool = false) {
        self.systemWatts = systemWatts
        self.adapterWatts = adapterWatts
        self.adapterRatedWatts = adapterRatedWatts
        self.adapterName = adapterName
        self.batteryWatts = batteryWatts
        self.voltage = voltage
        self.amperage = amperage
        self.batteryTemperature = batteryTemperature
        self.designCapacity = designCapacity
        self.fullCapacity = fullCapacity
        self.currentCapacity = currentCapacity
        self.isPluggedIn = isPluggedIn
        self.isFullyCharged = isFullyCharged
    }

    /// Whether there is anything to show at all.
    public var isEmpty: Bool { systemWatts == nil && adapterWatts == nil && batteryWatts == nil && adapterRatedWatts == nil }
}

public struct MetricsSnapshot: Sendable, Equatable {
    public var timestamp: Date
    public var cpu: Double
    public var gpu: Double?
    public var memory: MemoryStats
    public var network: NetworkRates
    public var disk: DiskStats
    public var battery: BatteryStats?
    public var temperatures: [String: Double]
    /// The load of each core, 0...1.
    public var cores: [Double]
    public var diskIO: DiskRates
    public var power: PowerStats?

    public init(timestamp: Date, cpu: Double, gpu: Double?, memory: MemoryStats, network: NetworkRates,
                disk: DiskStats, battery: BatteryStats?, temperatures: [String: Double],
                cores: [Double] = [], diskIO: DiskRates = .zero, power: PowerStats? = nil) {
        self.power = power
        self.cores = cores
        self.diskIO = diskIO
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.network = network
        self.disk = disk
        self.battery = battery
        self.temperatures = temperatures
    }
}

public protocol MetricsSources: Sendable {
    func cpuTicks() -> CPUTicks
    func gpuUsage() -> Double?
    func memory() -> MemoryStats
    func networkCounters() -> NetworkCounters
    func disk() -> DiskStats
    func battery() -> BatteryStats?
    func temperatures() -> [String: Double]
    /// Ticks for each core; empty where they cannot be read.
    func coreTicks() -> [CPUTicks]
    func diskCounters() -> DiskCounters?
    func power() -> PowerStats?
}

public extension MetricsSources {
    func coreTicks() -> [CPUTicks] { [] }
    func diskCounters() -> DiskCounters? { nil }
    func power() -> PowerStats? { nil }
}
