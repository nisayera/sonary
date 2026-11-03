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
