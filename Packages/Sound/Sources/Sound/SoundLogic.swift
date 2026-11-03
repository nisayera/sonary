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

/// The device after the current one, wrapping around. Nil when there is nothing to switch to.
public func nextOutputDevice(after current: UInt32?, in devices: [AudioDevice]) -> AudioDevice? {
    guard devices.count > 1 else { return nil }
    guard let current, let index = devices.firstIndex(where: { $0.id == current }) else { return devices.first }
    return devices[(index + 1) % devices.count]
}

/// Names that tell us a device is worn on the head, so unplugging it should not blast the speakers.
public func isHeadphoneLike(_ name: String) -> Bool {
    let lowered = name.lowercased()
    return ["airpods", "headphone", "kopfhörer", "headset", "beats", "earbuds", "buds", "wh-", "wf-"]
        .contains { lowered.contains($0) }
}

/// How loud the speakers may be right after headphones were disconnected.
public func volumeAfterUnplug(current: Double, limit: Double) -> Double {
    min(clampedVolume(current), clampedVolume(limit))
}
