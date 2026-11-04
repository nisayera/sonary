import AppKit
import CoreGraphics

/// Posts the keyboard shortcuts behind mapped mouse buttons.
enum SyntheticEvents {
    static func perform(_ action: ButtonAction) {
        switch action {
        case .none: break
        case .back: key(33, .maskCommand)          // Cmd+[
        case .forward: key(30, .maskCommand)       // Cmd+]
        case .missionControl: key(126, .maskControl) // Ctrl+Up
        case .appExpose: key(125, .maskControl)    // Ctrl+Down
        case .showDesktop: key(103, [])            // F11
        case .launchpad: key(160, [])              // Launchpad key
        case let .keyboardShortcut(keyCode, modifiers):
            key(keyCode, CGEventFlags(rawValue: modifiers))
        }
    }

    private static func key(_ keyCode: CGKeyCode, _ flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Posts a middle click where the pointer is, for the three-finger press.
    static func middleClick(at point: CGPoint) {
        for down in [true, false] {
            guard let event = CGEvent(mouseEventSource: nil,
                                      mouseType: down ? .otherMouseDown : .otherMouseUp,
                                      mouseCursorPosition: point, mouseButton: .center) else { continue }
            event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Posts a pixel-based scroll event. Such events are "continuous", so our own tap lets them pass.
    static func scroll(pixelsY: Int32, pixelsX: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: pixelsY, wheel2: pixelsX, wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }
}
