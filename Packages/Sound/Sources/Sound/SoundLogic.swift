import Foundation
import IOKit.pwr_mgt

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

/// The media keys macOS sends as system-defined events: play/pause, next and previous.
public enum MediaKey: Int, Sendable, CaseIterable {
    case playPause = 16
    case next = 17
    case previous = 18

    public init?(systemDefinedKeyCode code: Int) {
        self.init(rawValue: code)
    }
}

/// Whether Sonary should answer a media key itself instead of letting macOS wake a music app.
/// It only steps in when a player is already running, so the keys keep working as usual otherwise.
public func shouldHandleMediaKey(playersRunning: Bool, guardEnabled: Bool) -> Bool {
    guardEnabled && playersRunning
}

/// What keeps the Mac awake: a countdown, an app that is running, or being plugged in.
public enum KeepAwakeCondition: Codable, Equatable, Sendable {
    case duration(KeepAwakeDuration)
    case whileAppRuns(String)
    case whilePowered
    case whileDisplayConnected
}

/// The power assertion to take. Preventing *system* sleep is the only one that
/// also holds with the lid shut, so that mode asks for the stronger one.
public func keepAwakeAssertionType(closedLid: Bool) -> String {
    closedLid ? kIOPMAssertionTypePreventSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
}

/// Whether a running keep-awake still has a reason to hold. A countdown is
/// handled by its own timer, so it always says yes here.
public func keepAwakeShouldContinue(
    condition: KeepAwakeCondition, runningBundleIDs: [String], onPower: Bool,
    externalDisplays: Int = 0
) -> Bool {
    switch condition {
    case .duration: true
    case .whileAppRuns(let bundleID):
        runningBundleIDs.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    case .whilePowered: onPower
    case .whileDisplayConnected: externalDisplays > 0
    }
}
