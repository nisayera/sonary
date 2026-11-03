import Foundation

public enum ReadoutMetric: String, CaseIterable, Codable, Sendable {
    case cpu, memory, network, battery, temperature, fan
}

/// Human-readable transfer rate: "812 B/s", "200 KB/s", "1.5 MB/s". Decimal point is always ".".
public func formatRate(_ bytesPerSecond: Double) -> String {
    let value = max(0, bytesPerSecond)
    if value < 1_000 { return "\(Int(value.rounded())) B/s" }
    if value < 1_000_000 { return "\(Int((value / 1_000).rounded())) KB/s" }
    return String(format: "%.1f MB/s", value / 1_000_000)
}

/// Text for the menu bar, e.g. "CPU 42% · RAM 61%". Missing values show "—"; battery and fans are
/// omitted on Macs without them.
public func formatReadout(_ snapshot: MetricsSnapshot, metrics: [ReadoutMetric], fans: [FanReading] = []) -> String {
    metrics.compactMap { metric -> String? in
        switch metric {
        case .cpu:
            return "CPU \(Int((snapshot.cpu * 100).rounded()))%"
        case .memory:
            return "RAM \(Int((snapshot.memory.usedFraction * 100).rounded()))%"
        case .network:
            return "↓\(formatRate(snapshot.network.bytesInPerSec)) ↑\(formatRate(snapshot.network.bytesOutPerSec))"
        case .battery:
            guard let battery = snapshot.battery else { return nil }
            return "BAT \(Int((battery.level * 100).rounded()))%"
        case .temperature:
            guard let hottest = snapshot.temperatures.values.max() else { return "TEMP —" }
            return "TEMP \(Int(hottest.rounded()))°"
        case .fan:
            guard !fans.isEmpty else { return nil }
            return "FAN \(formatFanSpeed(fans))"
        }
    }
    .joined(separator: " · ")
}
