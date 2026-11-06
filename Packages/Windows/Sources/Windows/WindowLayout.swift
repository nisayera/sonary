import CoreGraphics
import Foundation

public enum LayoutAction: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case maximize, center, fillScreen

    /// Arrow and letter keys with ⌃⌥ (Carbon key codes).
    public var keyCode: Int {
        switch self {
        case .leftHalf: 123
        case .rightHalf: 124
        case .bottomHalf: 125
        case .topHalf: 126
        case .topLeft: 32      // U
        case .topRight: 34     // I
        case .bottomLeft: 38   // J
        case .bottomRight: 40  // K
        case .leftThird: 2     // D
        case .centerThird: 3   // F
        case .rightThird: 5    // G
        case .maximize: 36     // Return
        case .center: 8        // C
        case .fillScreen: 11     // B, for the whole screen including the menu bar
        }
    }

    public var shortcutLabel: String {
        let key: String = switch self {
        case .leftHalf: "←"
        case .rightHalf: "→"
        case .bottomHalf: "↓"
        case .topHalf: "↑"
        case .topLeft: "U"
        case .topRight: "I"
        case .bottomLeft: "J"
        case .bottomRight: "K"
        case .leftThird: "D"
        case .centerThird: "F"
        case .rightThird: "G"
        case .maximize: "↩"
        case .center: "C"
        case .fillScreen: "B"
        }
        return "⌃⌥" + key
    }
}

/// Target frame in Cocoa coordinates (origin bottom-left) inside a screen's visible frame.
/// `current` is only used for `.center`, which keeps the window's size.
public func layoutFrame(_ action: LayoutAction, visible v: CGRect, current: CGRect) -> CGRect {
    layoutFrame(action, visible: v, full: v, current: current)
}

/// The same, but told the screen's whole frame as well, which `.fillScreen` needs:
/// it covers the menu bar strip too, without macOS making a new Space for it.
public func layoutFrame(_ action: LayoutAction, visible v: CGRect, full: CGRect, current: CGRect) -> CGRect {
    let w = v.width, h = v.height
    let frame: CGRect = switch action {
    case .leftHalf: CGRect(x: v.minX, y: v.minY, width: w / 2, height: h)
    case .rightHalf: CGRect(x: v.midX, y: v.minY, width: w / 2, height: h)
    case .topHalf: CGRect(x: v.minX, y: v.midY, width: w, height: h / 2)
    case .bottomHalf: CGRect(x: v.minX, y: v.minY, width: w, height: h / 2)
    case .topLeft: CGRect(x: v.minX, y: v.midY, width: w / 2, height: h / 2)
    case .topRight: CGRect(x: v.midX, y: v.midY, width: w / 2, height: h / 2)
    case .bottomLeft: CGRect(x: v.minX, y: v.minY, width: w / 2, height: h / 2)
    case .bottomRight: CGRect(x: v.midX, y: v.minY, width: w / 2, height: h / 2)
    case .leftThird: CGRect(x: v.minX, y: v.minY, width: w / 3, height: h)
    case .centerThird: CGRect(x: v.minX + w / 3, y: v.minY, width: w / 3, height: h)
    case .rightThird: CGRect(x: v.minX + 2 * w / 3, y: v.minY, width: w / 3, height: h)
    case .maximize: v
    case .fillScreen: full
    case .center:
        CGRect(x: v.midX - min(current.width, w) / 2, y: v.midY - min(current.height, h) / 2,
               width: min(current.width, w), height: min(current.height, h))
    }
    return frame.integral
}

/// Accessibility uses a top-left origin measured from the top of the primary screen.
public func axRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
}

public func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
}

// MARK: - Quit protection

public enum ProtectedKey: String, Sendable, Equatable {
    case quit
    case close
}

/// How a protected shortcut is confirmed: press it twice, or hold it down.
public enum QuitConfirmation: String, CaseIterable, Codable, Sendable, Identifiable {
    case pressTwice, hold

    public var id: String { rawValue }
}

/// Holding a protected shortcut: it goes through once it has been held long enough.
/// Letting go early cancels, so a slip of the finger never quits anything.
public struct HoldGuard: Sendable {
    public var duration: Double
    private var heldSince: Double?
    private var held: String?

    public init(duration: Double = 0.6) { self.duration = duration }

    /// True between the first key-down of a hold and `up()`.
    public var isHolding: Bool { heldSince != nil }

    /// A key-down. Returns true when it has already been held long enough.
    public mutating func down(app: String, key: ProtectedKey, at time: Double) -> Bool {
        let identity = "\(app)#\(key.rawValue)"
        guard held == identity, let heldSince else {
            held = identity
            heldSince = time
            return false
        }
        return time - heldSince >= duration
    }

    /// Progress from 0 to 1, for the hint Sonary shows while the keys are down.
    public func progress(app: String, key: ProtectedKey, at time: Double) -> Double {
        guard held == "\(app)#\(key.rawValue)", let heldSince, duration > 0 else { return 0 }
        return min(max((time - heldSince) / duration, 0), 1)
    }

    public mutating func up() {
        held = nil
        heldSince = nil
    }
}

/// The shortcut has to be pressed twice within `window` seconds to go through.
public struct QuitGuard: Sendable {
    public var window: Double
    private var armedAt: Double?
    private var armed: String?

    public init(window: Double = 1.5) { self.window = window }

    /// Returns true when this press may pass through to the app.
    public mutating func shouldQuit(app: String, key: ProtectedKey = .quit, at time: Double) -> Bool {
        let identity = "\(app)#\(key.rawValue)"
        if let armedAt, armed == identity, time - armedAt >= 0, time - armedAt <= window {
            self.armedAt = nil
            armed = nil
            return true
        }
        armedAt = time
        armed = identity
        return false
    }
}

/// Empty list means every app is protected; otherwise only the listed ones are.
public func isProtected(bundleID: String, onlyApps: [String]) -> Bool {
    onlyApps.isEmpty || onlyApps.contains(bundleID)
}

/// The visible frame of the screen after the one the window is on, wrapping around.
/// Nil when there is only one screen.
public func nextScreen(after frame: CGRect, screens: [CGRect]) -> CGRect? {
    guard screens.count > 1 else { return nil }
    let centre = CGPoint(x: frame.midX, y: frame.midY)
    let index = screens.firstIndex { $0.contains(centre) } ?? 0
    return screens[(index + 1) % screens.count]
}

/// Keeps a window's place and size relative to its screen when it moves to another one.
public func movedFrame(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
    guard source.width > 0, source.height > 0 else { return frame }
    let relativeX = (frame.minX - source.minX) / source.width
    let relativeY = (frame.minY - source.minY) / source.height
    let width = min(frame.width / source.width, 1) * target.width
    let height = min(frame.height / source.height, 1) * target.height
    let x = target.minX + min(max(relativeX, 0), 1) * target.width
    let y = target.minY + min(max(relativeY, 0), 1) * target.height
    return CGRect(x: min(x, target.maxX - width), y: min(y, target.maxY - height),
                  width: width, height: height).integral
}

/// Apps whose last window just closed, so they can be quit. An app that never had a window
/// (a menu bar app, a helper) is never quit by this.
public func appsWithNoWindowsLeft(previous: [Int32: Int], current: [Int32: Int]) -> [Int32] {
    previous.compactMap { pid, count in
        guard count > 0, let now = current[pid], now == 0 else { return nil }
        return pid
    }
    .sorted()
}

/// Waits for an app's last window to be gone twice in a row before it is quit.
///
/// One look is not enough: a window can be absent from a single count for reasons that
/// have nothing to do with being closed, and quitting an app that still has work in it
/// cannot be undone. Two counts in a row cost two seconds and remove that class of
/// mistake.
public struct QuitWatchState: Sendable {
    /// What each app had at the last count, by process id.
    private var counts: [Int32: Int] = [:]
    /// How many counts in a row an app has had nothing, for the ones being watched.
    private var emptyChecks: [Int32: Int] = [:]

    public init() {}

    /// Feeds a fresh count and returns the apps whose last window has now been gone
    /// twice in a row. An app that never had a window is never returned, and an app
    /// missing from `current` — one whose count could not be read, or that has gone
    /// away — is left alone rather than treated as empty.
    public mutating func update(_ current: [Int32: Int]) -> [Int32] {
        for pid in emptyChecks.keys where current[pid] == 0 {
            emptyChecks[pid, default: 0] += 1
        }
        for pid in appsWithNoWindowsLeft(previous: counts, current: current) where emptyChecks[pid] == nil {
            emptyChecks[pid] = 1
        }
        // An app with a window again, or one that is gone, is no longer waiting.
        emptyChecks = emptyChecks.filter { pid, _ in current[pid] == 0 }
        let quit = emptyChecks.filter { $0.value >= 2 }.keys.sorted()
        // Asked once; if the app refuses or puts up a save dialog, it is not asked again.
        for pid in quit { emptyChecks.removeValue(forKey: pid) }
        counts = current
        return quit
    }

    /// Takes a first count without starting any waiting, for when the watcher begins.
    public mutating func prime(_ current: [Int32: Int]) {
        counts = current
        emptyChecks = [:]
    }
}

/// The layout's name as plain text, for places that cannot take a LocalizedStringKey,
/// such as the central shortcut page.
func layoutName(_ action: LayoutAction) -> String {
    switch action {
    case .leftHalf: String(localized: "Left half", bundle: .module)
    case .rightHalf: String(localized: "Right half", bundle: .module)
    case .topHalf: String(localized: "Top half", bundle: .module)
    case .bottomHalf: String(localized: "Bottom half", bundle: .module)
    case .topLeft: String(localized: "Top left quarter", bundle: .module)
    case .topRight: String(localized: "Top right quarter", bundle: .module)
    case .bottomLeft: String(localized: "Bottom left quarter", bundle: .module)
    case .bottomRight: String(localized: "Bottom right quarter", bundle: .module)
    case .leftThird: String(localized: "Left third", bundle: .module)
    case .centerThird: String(localized: "Center third", bundle: .module)
    case .rightThird: String(localized: "Right third", bundle: .module)
    case .maximize: String(localized: "Maximize", bundle: .module)
    case .center: String(localized: "Center", bundle: .module)
    case .fillScreen: String(localized: "Fill the screen", bundle: .module)
    }
}
