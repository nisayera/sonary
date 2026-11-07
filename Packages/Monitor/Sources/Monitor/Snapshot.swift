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

    public init(timestamp: Date, cpu: Double, gpu: Double?, memory: MemoryStats, network: NetworkRates,
                disk: DiskStats, battery: BatteryStats?, temperatures: [String: Double],
                cores: [Double] = [], diskIO: DiskRates = .zero) {
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
}

public extension MetricsSources {
    func coreTicks() -> [CPUTicks] { [] }
    func diskCounters() -> DiskCounters? { nil }
}
