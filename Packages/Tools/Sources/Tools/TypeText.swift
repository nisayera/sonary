import AppKit
import CoreGraphics

/// Marks the key events Sonary types itself, so its own snippet watcher does not read them
/// back as typing ("SONT").
let typedTextMarker: Int64 = 0x534F_4E54

/// Types text into whatever has the keyboard, a chunk at a time. Each event carries the
/// characters themselves rather than key codes, so it works on every keyboard layout.
@MainActor
enum TypeText {
    /// CGEvent takes up to 20 UTF-16 units per event; keep well under it.
    static let chunkSize = 16

    static func chunks(of text: String, size: Int = chunkSize) -> [[UniChar]] {
        let units = Array(text.utf16)
        guard size > 0, !units.isEmpty else { return [] }
        return stride(from: 0, to: units.count, by: size).map { start in
            Array(units[start..<min(start + size, units.count)])
        }
    }

    static func type(_ text: String) {
        for chunk in chunks(of: text) {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }
            chunk.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }
            down.setIntegerValueField(.eventSourceUserData, value: typedTextMarker)
            up.setIntegerValueField(.eventSourceUserData, value: typedTextMarker)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Deletes the characters just before the cursor, for replacing a typed trigger.
    static func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: down) else { continue }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: typedTextMarker)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
