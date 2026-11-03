import CoreGraphics

public enum LayoutAction: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case maximize, center

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
        }
        return "⌃⌥" + key
    }
}

/// Target frame in Cocoa coordinates (origin bottom-left) inside a screen's visible frame.
/// `current` is only used for `.center`, which keeps the window's size.
public func layoutFrame(_ action: LayoutAction, visible v: CGRect, current: CGRect) -> CGRect {
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
