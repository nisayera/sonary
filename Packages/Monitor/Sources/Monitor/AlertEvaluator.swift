import Foundation

public enum AlertKind: Sendable, Equatable, Hashable, CaseIterable {
    case sustainedCPU, highTemperature, memoryPressure, lowDisk, lowBattery
}

public struct AlertThresholds: Sendable, Equatable {
    public var cpu: Double = 0.9
    public var cpuDuration: TimeInterval = 30
    public var temperature: Double = 100
    public var diskFreeFraction: Double = 0.05
    public var batteryLevel: Double = 0.2
    public var cooldown: TimeInterval = 600

    public init() {}
}

/// Reports each alert kind once per episode: on the transition from "ok" to "alarm".
public struct AlertEvaluator: Sendable {
    private let thresholds: AlertThresholds
    private var active: Set<AlertKind> = []
    private var cpuHighSince: Date?
    private var lastFired: [AlertKind: Date] = [:]

    public init(thresholds: AlertThresholds = .init()) {
        self.thresholds = thresholds
    }

    public mutating func evaluate(_ snapshot: MetricsSnapshot) -> [AlertKind] {
        if snapshot.cpu >= thresholds.cpu {
            if cpuHighSince == nil { cpuHighSince = snapshot.timestamp }
        } else {
            cpuHighSince = nil
        }

        var now: Set<AlertKind> = []
        if let since = cpuHighSince, snapshot.timestamp.timeIntervalSince(since) >= thresholds.cpuDuration {
            now.insert(.sustainedCPU)
        }
        if let hottest = snapshot.temperatures.values.max(), hottest >= thresholds.temperature {
            now.insert(.highTemperature)
        }
        if snapshot.memory.pressure == .critical {
            now.insert(.memoryPressure)
        }
        if snapshot.disk.totalBytes > 0, snapshot.disk.freeFraction <= thresholds.diskFreeFraction {
            now.insert(.lowDisk)
        }
        if let battery = snapshot.battery, !battery.isCharging, battery.level <= thresholds.batteryLevel {
            now.insert(.lowBattery)
        }

        let fired = AlertKind.allCases.filter { kind in
            guard now.contains(kind), !active.contains(kind) else { return false }
            guard let last = lastFired[kind] else { return true }
            return snapshot.timestamp.timeIntervalSince(last) >= thresholds.cooldown
        }
        for kind in fired { lastFired[kind] = snapshot.timestamp }
        active = now
        return fired
    }
}
