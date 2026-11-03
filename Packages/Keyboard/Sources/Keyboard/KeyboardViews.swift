import AppKit
import SonaryUI
import SwiftUI

func sourceTitle(_ source: SuperKeySource) -> LocalizedStringKey {
    switch source {
    case .capsLock: "Caps Lock"
    case .rightCommand: "Right ⌘"
    case .rightOption: "Right ⌥"
    case .rightControl: "Right ⌃"
    }
}

func tapActionTitle(_ action: SuperKeyTapAction) -> LocalizedStringKey {
    switch action {
    case .none: "Nothing"
    case .escape: "Escape"
    case .commandBar: "Open the command bar"
    }
}

struct KeyboardSettingsView: View {
    let model: KeyboardModel

    var body: some View {
        SettingsCard(Text("Super Key", bundle: .module)) {
            SettingsToggleRow(symbol: "command", title: Text("Turn one key into ⌃⌥⇧⌘", bundle: .module),
                              caption: Text("Held down it adds all four modifiers, so you get shortcuts no app uses.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.superKeyEnabled },
                                            set: { value in model.update { $0.superKeyEnabled = value } }))
            if model.settings.superKeyEnabled {
                Divider()
                SettingsRow(symbol: "keyboard", title: Text("Key", bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.source },
                                              set: { value in model.update { $0.source = value } })) {
                        ForEach(SuperKeySource.allCases, id: \.self) { Text(sourceTitle($0), bundle: .module).tag($0) }
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 170)
                }
                SettingsRow(symbol: "hand.tap", title: Text("When tapped on its own", bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.tapAction },
                                              set: { value in model.update { $0.tapAction = value } })) {
                        ForEach(SuperKeyTapAction.allCases, id: \.self) { Text(tapActionTitle($0), bundle: .module).tag($0) }
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 190)
                }
                HStack(spacing: 8) {
                    Circle().fill(model.isHolding ? Color.green : Color.secondary.opacity(0.3)).frame(width: 9, height: 9)
                    Group {
                        if model.isHolding {
                            Text("Holding", bundle: .module)
                        } else {
                            Text("Hold the key to test it", bundle: .module)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        SettingsCard(Text("Debounce", bundle: .module)) {
            SettingsRow(symbol: "keyboard.badge.ellipsis",
                        title: model.settings.debounceMilliseconds == 0
                            ? Text("Key debounce: off", bundle: .module)
                            : Text("Ignore a repeated key within \(model.settings.debounceMilliseconds) ms", bundle: .module),
                        caption: Text("For keyboards whose switches send a letter twice.", bundle: .module)) {
                Stepper(value: Binding(get: { model.settings.debounceMilliseconds },
                                       set: { value in model.update { $0.debounceMilliseconds = value } }),
                        in: 0...120, step: 10) { EmptyView() }
                    .labelsHidden()
            }
        }
        if model.settings.superKeyEnabled {
            SettingsCard(Text("Exceptions", bundle: .module)) {
                Text("Super Key stays off while one of these apps is in front.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.settings.excludedApps, id: \.self) { bundleID in
                    SettingsRow(symbol: "app.dashed", title: Text(verbatim: bundleID)) {
                        Button(role: .destructive) {
                            model.update { $0.excludedApps.removeAll { $0 == bundleID } }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove exception", bundle: .module))
                    }
                }
                Button { addApp() } label: {
                    Label { Text("Add app…", bundle: .module) } icon: { Image(systemName: "plus") }
                }
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.update { if !$0.excludedApps.contains(id) { $0.excludedApps.append(id) } }
    }
}
