import AppKit
import ApplicationServices

/// What a key pressed in Finder turns into.
public enum FinderKeyAction: Equatable, Sendable {
    /// Not ours: Finder gets the key as it is.
    case pass
    /// ⌘X: copy the selection, so the next ⌘V moves it.
    case cut
    /// ⌘V after a cut: Finder's own "move here" (⌘⌥V) instead of a copy.
    case moveHere
    /// F2: start renaming, as Return does in Finder.
    case rename
}

/// Decides what a key press in Finder does. Nothing happens while text is being edited (a
/// file name, the search field), so ⌘X and ⌘V keep cutting and pasting text there.
public func finderKeyAction(keyCode: Int64, command: Bool, option: Bool, shift: Bool, control: Bool,
                            editingText: Bool, cutPending: Bool, cutAndPaste: Bool, renameWithF2: Bool)
    -> FinderKeyAction {
    guard !editingText, !control, !option, !shift else { return .pass }
    if cutAndPaste, command {
        if keyCode == 7 { return .cut }
        if keyCode == 9, cutPending { return .moveHere }
    }
    if renameWithF2, !command, keyCode == 120 { return .rename }
    return .pass
}

/// Marks the keys Sonary presses for Finder, so its own tap lets them through ("SONF").
let finderKeysMarker: Int64 = 0x534F_4E46

private func finderKeysCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<FinderKeysTap>.fromOpaque(userInfo).takeUnretainedValue()
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isOurs = event.getIntegerValueField(.eventSourceUserData) == finderKeysMarker
    let keep = MainActor.assumeIsolated {
        tap.handle(type: type, keyCode: keyCode, flags: flags, isOurs: isOurs)
    }
    return keep ? Unmanaged.passUnretained(event) : nil
}

/// ⌘X and ⌘V that move files, and F2 that renames, while Finder is in front. Finder already
/// moves copied files with ⌘⌥V; this only maps the keys people expect onto it.
@MainActor
final class FinderKeysTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    var cutAndPaste = false
    var renameWithF2 = false
    /// The pasteboard's count right after a cut. While it still matches, ⌘V moves.
    private var cutChangeCount: Int?

    /// False when the tap could not be created, which means Accessibility is missing.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: finderKeysCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        cutChangeCount = nil
    }

    /// True to let the key through.
    func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isOurs: Bool) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return true
        }
        guard type == .keyDown, !isOurs,
              let finder = NSWorkspace.shared.frontmostApplication, finder.bundleIdentifier == "com.apple.finder"
        else { return true }
        // Only ask Finder what is focused for the keys that could be ours.
        guard [7, 9, 120].contains(keyCode) else { return true }
        let cutPending = cutChangeCount == NSPasteboard.general.changeCount
        let action = finderKeyAction(
            keyCode: keyCode, command: flags.contains(.maskCommand), option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift), control: flags.contains(.maskControl),
            editingText: Self.isEditingText(in: finder.processIdentifier), cutPending: cutPending,
            cutAndPaste: cutAndPaste, renameWithF2: renameWithF2)
        switch action {
        case .pass:
            return true
        case .cut:
            Self.press(8, flags: .maskCommand)
            Task { @MainActor in
                // Finder writes the copy a moment later; remember the pasteboard after that.
                try? await Task.sleep(for: .milliseconds(250))
                self.cutChangeCount = NSPasteboard.general.changeCount
            }
            return false
        case .moveHere:
            cutChangeCount = nil
            Self.press(9, flags: [.maskCommand, .maskAlternate])
            return false
        case .rename:
            Self.press(36, flags: [])
            return false
        }
    }

    /// Whether Finder is editing text right now: a file name, the search field, a path.
    private static func isEditingText(in pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(unsafeDowncast(focused, to: AXUIElement.self), kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String else { return false }
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role)
    }

    private static func press(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: finderKeysMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
