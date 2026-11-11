import AppKit
import CoreGraphics
import SonaryCore

/// Watches the keyboard for snippet triggers and has them replaced by their snippet. Needs
/// Accessibility; password fields are never seen, macOS keeps them from every tap.
@MainActor
final class SnippetTriggerTap {
    /// Listens only: every event goes on unchanged. Appended at the tail, after the taps that
    /// may swallow keys, so it sees what really reaches the app.
    private lazy var tap: EventTap = {
        let tap = EventTap(mask: EventTap.mask([.keyDown, .leftMouseDown, .rightMouseDown]),
                           place: .tailAppendEventTap) { [weak self] type, event in
            switch type {
            case .leftMouseDown, .rightMouseDown:
                MainActor.assumeIsolated { self?.reset() }
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
                MainActor.assumeIsolated { self?.keyDown(typed: typed, keyCode: keyCode, isShortcut: isShortcut) }
            default:
                break
            }
            return .pass
        }
        tap.onReenable = { [weak self] in self?.watcher.reset() }
        return tap
    }()
    private var watcher = SnippetTriggerWatcher()
    /// The snippets with their triggers, read at every key press so edits apply at once.
    var snippets: () -> [Snippet] = { [] }
    /// Called with the snippet whose trigger was just typed.
    var expand: (Snippet) -> Void = { _ in }

    var isRunning: Bool { tap.isRunning }

    /// False when the tap could not be created, which means Accessibility is missing.
    @discardableResult
    func start() -> Bool {
        guard !tap.isRunning else { return true }
        guard tap.start() else { return false }
        watcher.reset()
        return true
    }

    func stop() {
        tap.stop()
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
