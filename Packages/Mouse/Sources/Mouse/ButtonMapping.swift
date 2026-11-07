import CoreGraphics
import Foundation
import SonaryCore

public enum ButtonAction: Codable, Equatable, Sendable {
    case none
    case back
    case forward
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case keyboardShortcut(keyCode: UInt16, modifiers: UInt64)
}

/// The key of a shortcut action that has been chosen but not recorded yet: it does nothing.
public let unrecordedKeyCode = UInt16.max

/// What the settings show for a shortcut action, such as "⌃⌘F". Empty when not recorded.
public func shortcutLabel(keyCode: UInt16, modifiers: UInt64) -> String {
    guard keyCode != unrecordedKeyCode else { return "" }
    let flags = CGEventFlags(rawValue: modifiers)
    var text = ""
    if flags.contains(.maskControl) { text += "⌃" }
    if flags.contains(.maskAlternate) { text += "⌥" }
    if flags.contains(.maskShift) { text += "⇧" }
    if flags.contains(.maskCommand) { text += "⌘" }
    return text + keyName(Int(keyCode))
}

/// The modifier keys of a recorded shortcut as the event flags it is sent with.
public func shortcutModifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> UInt64 {
    var flags = CGEventFlags()
    if command { flags.insert(.maskCommand) }
    if option { flags.insert(.maskAlternate) }
    if control { flags.insert(.maskControl) }
    if shift { flags.insert(.maskShift) }
    return flags.rawValue
}

public struct ButtonMapping: Codable, Equatable, Sendable {
    public var button: Int
    public var action: ButtonAction

    public init(button: Int, action: ButtonAction) {
        self.button = button
        self.action = action
    }
}

/// Buttons 0...2 (left, right, middle) are never remapped, so a bad mapping cannot lock the user out.
public func action(forButton button: Int, in mappings: [ButtonMapping]) -> ButtonAction? {
    guard button > 2 else { return nil }
    return mappings.first { $0.button == button }?.action
}

/// Which way the mouse was pushed while an extra button was held.
public enum GestureDirection: String, CaseIterable, Codable, Sendable, Identifiable {
    case up, down, left, right

    public var id: String { rawValue }
}

/// The direction of a drag, or nil when it was too short to have meant one. The longer
/// axis decides, so a slightly crooked push still reads as the one intended.
public func gestureDirection(from origin: CGPoint, to point: CGPoint,
                             threshold: CGFloat = 28) -> GestureDirection? {
    let dx = point.x - origin.x
    let dy = point.y - origin.y
    guard max(abs(dx), abs(dy)) >= threshold else { return nil }
    if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
    return dy > 0 ? .up : .down
}

/// What holding an extra button and pushing the mouse in one direction does.
public struct GestureMapping: Codable, Equatable, Sendable, Identifiable {
    public var button: Int
    public var direction: GestureDirection
    public var action: ButtonAction
    public var id: String { "\(button)-\(direction.rawValue)" }

    public init(button: Int, direction: GestureDirection, action: ButtonAction) {
        self.button = button
        self.direction = direction
        self.action = action
    }
}

/// The gesture for this button and direction, if one is set. Buttons 0...2 are left
/// alone here too, so the three ordinary buttons keep working.
public func action(forGesture button: Int, direction: GestureDirection,
                   in mappings: [GestureMapping]) -> ButtonAction? {
    guard button > 2 else { return nil }
    return mappings.first { $0.button == button && $0.direction == direction }?.action
}

/// Whether a button has any gesture at all, which is what decides whether its click
/// has to wait to find out if it was a gesture instead.
public func hasGestures(button: Int, in mappings: [GestureMapping]) -> Bool {
    mappings.contains { $0.button == button }
}

/// A sideways wheel reports on its own axis. Which way it was turned, or nil when it
/// was not turned at all.
public func sideWheelDirection(deltaX: Double) -> GestureDirection? {
    guard deltaX != 0 else { return nil }
    return deltaX > 0 ? .right : .left
}
