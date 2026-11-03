import Foundation

public enum SuperKeySource: String, Codable, CaseIterable, Sendable {
    case capsLock, rightCommand, rightOption, rightControl

    public var keyCode: Int64 {
        switch self {
        case .capsLock: 57
        case .rightCommand: 54
        case .rightOption: 61
        case .rightControl: 62
        }
    }
}

public enum SuperKeyTapAction: String, Codable, CaseIterable, Sendable {
    case none, escape, commandBar
}

/// What the tap should do with the key press it just saw.
public enum SuperKeyOutcome: Equatable, Sendable {
    /// Let the event through unchanged.
    case pass
    /// Swallow the event.
    case swallow
    /// Swallow it and run the tap action.
    case tap
    /// Let the key through, but with the hyper modifiers added.
    case hyper
}

/// Turns one key into a hyper modifier: held down it adds ⌃⌥⇧⌘ to other keys,
/// tapped on its own it runs the tap action.
public struct SuperKeyEngine: Equatable, Sendable {
    /// A press longer than this never counts as a tap, even on its own.
    public var tapTimeout: Double
    public private(set) var isHolding = false
    private var pressedAt: Double?
    private var usedAsModifier = false

    public init(tapTimeout: Double = 0.5) {
        self.tapTimeout = tapTimeout
    }

    public mutating func sourcePressed(at time: Double) -> SuperKeyOutcome {
        pressedAt = time
        isHolding = true
        usedAsModifier = false
        return .swallow
    }

    public mutating func sourceReleased(at time: Double) -> SuperKeyOutcome {
        defer {
            isHolding = false
            pressedAt = nil
            usedAsModifier = false
        }
        guard let pressedAt, !usedAsModifier, time - pressedAt >= 0, time - pressedAt <= tapTimeout else {
            return .swallow
        }
        return .tap
    }

    /// Another key was pressed; while the source is held it becomes a hyper shortcut.
    public mutating func otherKeyPressed() -> SuperKeyOutcome {
        guard isHolding else { return .pass }
        usedAsModifier = true
        return .hyper
    }

    /// The source key is let go without a release event (app lost the tap, screen locked, ...).
    public mutating func reset() {
        isHolding = false
        pressedAt = nil
        usedAsModifier = false
    }
}

public struct KeyboardSettings: Codable, Equatable, Sendable {
    public var superKeyEnabled = false
    public var source: SuperKeySource = .capsLock
    public var tapAction: SuperKeyTapAction = .escape
    public var excludedApps: [String] = []
    /// Ignores a second press of the same key within this many milliseconds; 0 is off.
    public var debounceMilliseconds = 0

    public init() {}
}

/// Super Key is off while one of the excluded apps is in front.
public func superKeyActive(_ settings: KeyboardSettings, bundleID: String?) -> Bool {
    guard settings.superKeyEnabled else { return false }
    guard let bundleID else { return true }
    return !settings.excludedApps.contains(bundleID)
}

/// Drops key presses that repeat faster than a person can type, for keyboards whose
/// switches bounce and send a letter twice.
public struct KeyDebouncer: Sendable {
    private let windowNanoseconds: UInt64
    private var lastPress: [Int64: UInt64] = [:]

    public init(milliseconds: Int) {
        windowNanoseconds = UInt64(max(milliseconds, 0)) * 1_000_000
    }

    public mutating func shouldDrop(keyCode: Int64, timestampNanoseconds: UInt64) -> Bool {
        guard windowNanoseconds > 0 else { return false }
        if let last = lastPress[keyCode], timestampNanoseconds >= last,
           timestampNanoseconds - last < windowNanoseconds {
            return true
        }
        lastPress[keyCode] = timestampNanoseconds
        return false
    }
}
