import Foundation
import IOKit

/// Drops implausible readings (non-positive or above 150 °C).
public func normalizeTemperatures(_ raw: [String: Double]) -> [String: Double] {
    raw.filter { $0.value > 0 && $0.value <= 150 }
}

/// GPU utilization and chip temperatures. Every failure degrades to `nil` / `[:]`.
public final class SystemSensorReader: SensorReading, @unchecked Sendable {
    private let gpuSource: @Sendable () -> Double?
    private let temperatureSource: @Sendable () -> [String: Double]

    public init(
        gpu: @escaping @Sendable () -> Double?,
        temperatures: @escaping @Sendable () -> [String: Double]
    ) {
        self.gpuSource = gpu
        self.temperatureSource = temperatures
    }

    public convenience init() {
        let provider = SMCTemperatureProvider()
        self.init(gpu: { readAcceleratorUtilization() }, temperatures: { provider.read() })
    }

    public func gpuUsage() -> Double? {
        guard let value = gpuSource(), value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    public func temperatures() -> [String: Double] {
        normalizeTemperatures(temperatureSource())
    }
}

/// "Device Utilization %" published by the graphics accelerator (AGXAccelerator on Apple Silicon), 0...1.
func readAcceleratorUtilization() -> Double? {
    var iterator = io_iterator_t()
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess else {
        return nil
    }
    defer { IOObjectRelease(iterator) }
    while case let entry = IOIteratorNext(iterator), entry != 0 {
        defer { IOObjectRelease(entry) }
        guard let reference = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
              let stats = reference.takeRetainedValue() as? [String: Any],
              let utilization = stats["Device Utilization %"] as? Int else { continue }
        return Double(utilization) / 100
    }
    return nil
}

/// Reads grouped chip temperatures ("CPU", "GPU", "Battery") from the SMC. Opens the SMC lazily, once.
final class SMCTemperatureProvider: @unchecked Sendable {
    private struct Group {
        let label: String
        var keys: [SMCClient.Key]
    }

    private let lock = NSLock()
    private var client: SMCClient?
    private var groups: [Group] = []
    private var prepared = false

    func read() -> [String: Double] {
        lock.lock()
        defer { lock.unlock() }
        prepare()
        guard let client else { return [:] }
        var result: [String: Double] = [:]
        for group in groups {
            let values = group.keys.compactMap { client.readValue($0) }.filter { $0 > 1 && $0 < 125 }
            if let maximum = values.max() { result[group.label] = maximum }
        }
        return result
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        guard let client = SMCClient() else { return }
        self.client = client
        let all = client.keys { name in
            name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg")
                || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        groups = [
            Group(label: "CPU", keys: all.filter { $0.name.hasPrefix("Tp") || $0.name.hasPrefix("Te") }),
            Group(label: "GPU", keys: all.filter { $0.name.hasPrefix("Tg") }),
            Group(label: "Battery", keys: all.filter { $0.name.hasPrefix("TB") }),
        ].filter { !$0.keys.isEmpty }
    }
}
