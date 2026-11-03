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

    public init(level: Double, isCharging: Bool, watts: Double? = nil, minutesRemaining: Int? = nil) {
        self.level = level
        self.isCharging = isCharging
        self.watts = watts
        self.minutesRemaining = minutesRemaining
    }
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

    public init(timestamp: Date, cpu: Double, gpu: Double?, memory: MemoryStats, network: NetworkRates,
                disk: DiskStats, battery: BatteryStats?, temperatures: [String: Double]) {
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
}
