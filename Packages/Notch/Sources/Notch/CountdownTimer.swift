import Foundation

public struct CountdownTimer: Equatable, Sendable {
    public private(set) var endsAt: Date?
    public private(set) var duration: TimeInterval = 0

    public init() {}

    public var isRunning: Bool { endsAt != nil }

    public mutating func start(duration: TimeInterval, at now: Date) {
        self.duration = max(0, duration)
        endsAt = now.addingTimeInterval(self.duration)
    }

    public mutating func cancel() {
        endsAt = nil
        duration = 0
    }

    public func remaining(at now: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    public func isFinished(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }
}

/// "4:05" or "1:02:03".
public func formatCountdown(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.up))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
