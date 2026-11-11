import AppKit
import SonaryCore
import SonaryUI
import SwiftUI

/// Every Sonary shortcut on one page: click a row to record a new combination,
/// ⌫ switches a shortcut off, and ⎋ keeps what was there.
struct ShortcutsPage: View {
    private let store = ShortcutStore.shared
    @State private var recording: String?

    var body: some View {
        SettingsPage {
            SettingsPageHeader(
                symbol: "keyboard", title: Text("Shortcuts"),
                subtitle: Text("Click a shortcut to record a new one. Press ⌫ to switch it off, ⎋ to keep it as it is.")
            )
        } content: {
            ForEach(groups, id: \.self) { group in
                SettingsCard(Text(verbatim: group)) {
                    ForEach(store.definitions.filter { $0.group == group }) { definition in
                        ShortcutRow(definition: definition, store: store,
                                    isRecording: recording == definition.id) {
                            recording = recording == definition.id ? nil : definition.id
                        } finished: {
                            recording = nil
                        }
                    }
                }
            }
            if store.definitions.isEmpty {
                SettingsCard(Text("Shortcuts")) {
                    Text("Turn a module on to see the shortcuts it offers.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var groups: [String] {
        var seen: [String] = []
        for definition in store.definitions where !seen.contains(definition.group) {
            seen.append(definition.group)
        }
        return seen
    }
}

private struct ShortcutRow: View {
    let definition: ShortcutDefinition
    let store: ShortcutStore
    let isRecording: Bool
    let toggle: () -> Void
    let finished: () -> Void
    @State private var problem: ShortcutProblem?

    var body: some View {
        SettingsRow(symbol: "command", title: Text(verbatim: definition.title),
                    caption: problemText) {
            HStack(spacing: 6) {
                Button(action: toggle) {
                    Text(verbatim: isRecording
                         ? String(localized: "Press keys…")
                         : displayed)
                        .font(.body.monospaced())
                        .frame(minWidth: 90)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? Color.sonaryAccent : nil)
                if store.isCustom(definition.id) {
                    Button {
                        store.set(nil, for: definition.id)
                        problem = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Back to the shortcut Sonary ships with"))
                    .accessibilityLabel(Text("Back to the shortcut Sonary ships with"))
                }
            }
        }
        .background { if isRecording { KeyRecorder(onKey: record, onCancel: finished) } }
    }

    private var displayed: String {
        let combo = store.combo(for: definition.id)
        return combo.isEmpty ? String(localized: "Off") : shortcutDisplay(combo)
    }

    private var problemText: Text? {
        switch problem {
        case .needsModifier: Text("Add ⌃, ⌥, ⇧ or ⌘ — a plain key would be caught everywhere.")
        case .takenBy(let other): Text("Already used by \(other).")
        case nil: nil
        }
    }

    private func record(_ combo: KeyCombo?) {
        guard let combo else {
            store.set(KeyCombo.none, for: definition.id)
            problem = nil
            finished()
            return
        }
        if let found = shortcutProblem(combo, for: definition.id, taken: store.inUse, titles: store.titles) {
            problem = found
            return
        }
        problem = nil
        store.set(combo, for: definition.id)
        finished()
    }
}

/// Catches the next key press for the row that is recording. Nil means "switch it off".
private struct KeyRecorder: NSViewRepresentable {
    let onKey: (KeyCombo?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onKey = onKey
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onKey = onKey
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    final class RecorderView: NSView {
        var onKey: ((KeyCombo?) -> Void)?
        var onCancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 53: onCancel?()                     // ⎋ keeps what was there
            case 51: onKey?(nil)                     // ⌫ switches it off
            default: onKey?(KeyCombo(keyCode: Int(event.keyCode),
                                     modifiers: carbonModifiers(event.modifierFlags)))
            }
        }

        override func flagsChanged(with event: NSEvent) {}
    }
}

/// AppKit's modifier flags as the Carbon flags the hot key API wants.
func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
    var value = 0
    if flags.contains(.command) { value |= KeyModifier.command }
    if flags.contains(.shift) { value |= KeyModifier.shift }
    if flags.contains(.option) { value |= KeyModifier.option }
    if flags.contains(.control) { value |= KeyModifier.control }
    return value
}
