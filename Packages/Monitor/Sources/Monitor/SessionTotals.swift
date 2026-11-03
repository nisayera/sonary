import Foundation

/// Bytes seen since the module was switched on.
public struct NetworkTotals: Equatable, Sendable {
    public var bytesIn: UInt64 = 0
    public var bytesOut: UInt64 = 0

    public init(bytesIn: UInt64 = 0, bytesOut: UInt64 = 0) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    /// Adds the step between two counter readings. A counter that went backwards
    /// (32-bit wraparound, interface change, wake from sleep) adds nothing instead of a huge jump.
    public mutating func add(previous: NetworkCounters, current: NetworkCounters) {
        if current.bytesIn >= previous.bytesIn { bytesIn += current.bytesIn - previous.bytesIn }
        if current.bytesOut >= previous.bytesOut { bytesOut += current.bytesOut - previous.bytesOut }
    }
}

public struct ProcessUsage: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var name: String
    public var cpu: Double
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpu: Double) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
    }
}

/// Reads `ps -Ao pid=,pcpu=,comm=` output: the busiest processes first, by their own name
/// rather than the full path. Sonary itself is left out.
public func parseProcessUsage(_ output: String, limit: Int, excluding ownPID: Int32 = 0) -> [ProcessUsage] {
    output.split(separator: "\n").compactMap { line -> ProcessUsage? in
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, let pid = Int32(parts[0]), let cpu = Double(parts[1]), pid != ownPID else { return nil }
        let path = parts[2].trimmingCharacters(in: .whitespaces)
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return ProcessUsage(pid: pid, name: name, cpu: cpu)
    }
    .sorted { $0.cpu > $1.cpu }
    .prefix(max(0, limit))
    .map { $0 }
}

/// Rough time left on battery, from its level and how fast it is falling. Nil while charging
/// or before two readings exist.
public func batteryTimeRemaining(levels: [(level: Double, at: Date)], now: Date) -> TimeInterval? {
    guard let first = levels.first, let last = levels.last, levels.count >= 2 else { return nil }
    let seconds = last.at.timeIntervalSince(first.at)
    let drop = first.level - last.level
    guard seconds >= 60, drop > 0 else { return nil }
    let perSecond = drop / seconds
    return last.level / perSecond
}

/// "2 h 05 min", or "45 min" under an hour.
public func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%d h %02d min", hours, minutes) : "\(minutes) min"
}
