import Foundation

public struct AudioDevice: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var name: String
    public var hasOutput: Bool
    public var hasInput: Bool

    public init(id: UInt32, name: String, hasOutput: Bool, hasInput: Bool) {
        self.id = id
        self.name = name
        self.hasOutput = hasOutput
        self.hasInput = hasInput
    }
}

/// Output devices first by name; devices without the wanted direction are left out.
public func devices(_ all: [AudioDevice], output: Bool) -> [AudioDevice] {
    all.filter { output ? $0.hasOutput : $0.hasInput }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// Clamps a volume to 0...1 and snaps tiny values to 0 so "muted" really is silent.
public func clampedVolume(_ value: Double) -> Double {
    let clamped = min(max(value, 0), 1)
    return clamped < 0.005 ? 0 : clamped
}

public enum KeepAwakeDuration: Int, CaseIterable, Codable, Sendable {
    case fifteenMinutes = 900, oneHour = 3600, twoHours = 7200, indefinitely = 0

    public var seconds: TimeInterval? { rawValue == 0 ? nil : TimeInterval(rawValue) }
}

/// Remaining keep-awake time, or nil when it runs until turned off.
public func keepAwakeRemaining(endsAt: Date?, now: Date) -> TimeInterval? {
    guard let endsAt else { return nil }
    return max(0, endsAt.timeIntervalSince(now))
}
