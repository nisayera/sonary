import Foundation

public enum AlertKind: Sendable, Equatable, Hashable, CaseIterable {
    case sustainedCPU, highTemperature, memoryPressure, lowDisk, lowBattery
}

public struct AlertThresholds: Sendable, Equatable {
    public var cpu: Double = 0.9
    public var cpuDuration: TimeInterval = 30
    public var temperature: Double = 95
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

        let fired = AlertKind.allCases.filter { now.contains($0) && !active.contains($0) }
        active = now
        return fired
    }
}
