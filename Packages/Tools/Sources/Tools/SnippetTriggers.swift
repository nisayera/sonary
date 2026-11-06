import AppKit
import CoreGraphics

private func snippetTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let watcher = Unmanaged<SnippetTriggerTap>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { watcher.reenable() }
    case .leftMouseDown, .rightMouseDown:
        MainActor.assumeIsolated { watcher.reset() }
    case .keyDown:
        // What Sonary types itself is never read back as typing.
        guard event.getIntegerValueField(.eventSourceUserData) != typedTextMarker else { break }
        let capacity = 8
        var length = 0
        var buffer = [UniChar](repeating: 0, count: capacity)
        event.keyboardGetUnicodeString(maxStringLength: capacity, actualStringLength: &length,
                                       unicodeString: &buffer)
        let typed = String(utf16CodeUnits: buffer, count: length)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isShortcut = event.flags.contains(.maskCommand) || event.flags.contains(.maskControl)
        MainActor.assumeIsolated { watcher.keyDown(typed: typed, keyCode: keyCode, isShortcut: isShortcut) }
    default:
        break
    }
    // The tap only listens: every event goes on unchanged.
    return Unmanaged.passUnretained(event)
}

/// Watches the keyboard for snippet triggers and has them replaced by their snippet. Needs
/// Accessibility; password fields are never seen, macOS keeps them from every tap.
@MainActor
final class SnippetTriggerTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watcher = SnippetTriggerWatcher()
    /// The snippets with their triggers, read at every key press so edits apply at once.
    var snippets: () -> [Snippet] = { [] }
    /// Called with the snippet whose trigger was just typed.
    var expand: (Snippet) -> Void = { _ in }

    var isRunning: Bool { tap != nil }

    /// False when the tap could not be created, which means Accessibility is missing.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: snippetTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        watcher.reset()
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        watcher.reset()
    }

    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        watcher.reset()
    }

    func reset() {
        watcher.reset()
    }

    func keyDown(typed: String, keyCode: Int64, isShortcut: Bool) {
        if isShortcut {
            watcher.reset()
            return
        }
        switch keyCode {
        case 51:
            watcher.backspace()
            return
        // Return, Tab, Escape, Enter and the keys that move the cursor.
        case 36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126:
            watcher.reset()
            return
        default:
            break
        }
        if let match = watcher.type(typed, snippets: snippets()) {
            expand(match)
        }
    }
}
