import Foundation

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
