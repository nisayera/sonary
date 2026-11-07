import AppKit
import SwiftUI

/// A button that shows a shortcut and, once clicked, records the next key press with its
/// modifiers. Escape stops recording and keeps what was there.
/// The texts come from the caller, which owns the translations.
public struct KeyPressRecorderButton: View {
    private let current: String
    private let recordTitle: Text
    private let recordingTitle: Text
    private let record: (UInt16, NSEvent.ModifierFlags) -> Void
    @State private var isRecording = false

    /// `current` is what the button shows while not recording, such as "⌘⇧4"; when it is
    /// empty the button shows `recordTitle`, and `recordingTitle` while it listens.
    public init(current: String, recordTitle: Text, recordingTitle: Text,
                record: @escaping (_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Void) {
        self.current = current
        self.recordTitle = recordTitle
        self.recordingTitle = recordingTitle
        self.record = record
    }

    public var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Group {
                if isRecording {
                    recordingTitle
                } else if current.isEmpty {
                    recordTitle
                } else {
                    Text(verbatim: current).monospaced()
                }
            }
            .frame(minWidth: 90)
        }
        .background {
            if isRecording {
                KeyPressCatcher { keyCode, modifiers in
                    isRecording = false
                    record(keyCode, modifiers)
                } cancel: {
                    isRecording = false
                }
            }
        }
    }
}

/// Catches the next key press while it is in a window.
struct KeyPressCatcher: NSViewRepresentable {
    let onKey: (UInt16, NSEvent.ModifierFlags) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onKey = onKey
        view.cancel = cancel
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onKey = onKey
        view.cancel = cancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    final class CatcherView: NSView {
        var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
        var cancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                cancel?()
            } else {
                onKey?(event.keyCode, event.modifierFlags.intersection([.command, .option, .control, .shift]))
            }
        }

        override func flagsChanged(with event: NSEvent) {}
    }
}
