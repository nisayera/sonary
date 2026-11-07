import Foundation

public enum ReadoutMetric: String, CaseIterable, Codable, Sendable {
    case cpu, memory, network, disk, battery, temperature, fan
}

/// A share drawn as one block, from ▁ to █, for a menu bar that shows bars.
public func usageBar(_ fraction: Double) -> String {
    let blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    let index = Int((min(max(fraction, 0), 1) * Double(blocks.count - 1)).rounded())
    return blocks[index]
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
public func formatReadout(_ snapshot: MetricsSnapshot, metrics: [ReadoutMetric], fans: [FanReading] = [],
                          bars: Bool = false, batteryTime: TimeInterval? = nil) -> String {
    readoutItems(snapshot, metrics: metrics, fans: fans, bars: bars, batteryTime: batteryTime)
        .map(\.text).joined(separator: " · ")
}

/// Each metric's own piece of the readout, for a menu bar item per metric. With `bars`,
/// shares show as a block instead of a number.
public func readoutItems(_ snapshot: MetricsSnapshot, metrics: [ReadoutMetric], fans: [FanReading] = [],
                         bars: Bool = false, batteryTime: TimeInterval? = nil) -> [(metric: ReadoutMetric, text: String)] {
    func share(_ label: String, _ fraction: Double) -> String {
        bars ? "\(label) \(usageBar(fraction))" : "\(label) \(Int((fraction * 100).rounded()))%"
    }
    return metrics.compactMap { metric -> (metric: ReadoutMetric, text: String)? in
        let text: String? = switch metric {
        case .cpu: share("CPU", snapshot.cpu)
        case .memory: share("RAM", snapshot.memory.usedFraction)
        case .network: "↓\(formatRate(snapshot.network.bytesInPerSec)) ↑\(formatRate(snapshot.network.bytesOutPerSec))"
        case .disk: "R \(formatRate(snapshot.diskIO.readPerSec)) W \(formatRate(snapshot.diskIO.writePerSec))"
        case .battery: snapshot.battery.map { battery in
            let time = batteryTime.map { " " + formatClockDuration($0) } ?? ""
            return share("BAT", battery.level) + time
        }
        case .temperature: snapshot.temperatures.values.max().map { "TEMP \(Int($0.rounded()))°" } ?? "TEMP —"
        case .fan: fans.isEmpty ? nil : "FAN \(formatFanSpeed(fans))"
        }
        return text.map { (metric, $0) }
    }
}

/// A duration as hours and minutes on a clock, "3:05".
public func formatClockDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return String(format: "%d:%02d", minutes / 60, minutes % 60)
}
