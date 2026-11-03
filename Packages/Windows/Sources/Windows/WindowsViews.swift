import AppKit
import SonaryUI
import SwiftUI

func layoutTitle(_ action: LayoutAction) -> LocalizedStringKey {
    switch action {
    case .leftHalf: "Left half"
    case .rightHalf: "Right half"
    case .topHalf: "Top half"
    case .bottomHalf: "Bottom half"
    case .topLeft: "Top left quarter"
    case .topRight: "Top right quarter"
    case .bottomLeft: "Bottom left quarter"
    case .bottomRight: "Bottom right quarter"
    case .leftThird: "Left third"
    case .centerThird: "Center third"
    case .rightThird: "Right third"
    case .maximize: "Maximize"
    case .center: "Center"
    }
}

struct WindowsSettingsView: View {
    let model: WindowsModel

    var body: some View {
        SettingsCard(Text("Window layouts", bundle: .module)) {
            SettingsToggleRow(symbol: "rectangle.split.2x1", title: Text("Keyboard shortcuts for window layouts", bundle: .module),
                              caption: Text("Moves and resizes the front window.", bundle: .module),
                              isOn: Binding(get: { model.settings.layoutShortcuts },
                                            set: { value in model.update { $0.layoutShortcuts = value } }))
            if model.settings.layoutShortcuts {
                Divider()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(LayoutAction.allCases, id: \.self) { action in
                        HStack {
                            Text(layoutTitle(action), bundle: .module)
                            Spacer()
                            Text(verbatim: action.shortcutLabel).font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Move to the next display", bundle: .module)
                        Spacer()
                        Text(verbatim: "⌃⌥\\").font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Put the window back", bundle: .module)
                        Spacer()
                        Text(verbatim: "⌃⌥⌫").font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        SettingsCard(Text("Window switcher", bundle: .module)) {
            SettingsToggleRow(symbol: "rectangle.stack", title: Text("Window switcher on ⌃⌥Tab", bundle: .module),
                              caption: Text("Lists every open window with search, and brings the one you pick to the front.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.windowSwitcher },
                                            set: { value in model.update { $0.windowSwitcher = value } }))
            if model.settings.windowSwitcher {
                Button { model.showSwitcher() } label: { Text("Show it now", bundle: .module) }
                    .buttonStyle(.borderless)
            }
        }
        SettingsCard(Text("Closing", bundle: .module)) {
            SettingsToggleRow(symbol: "xmark.circle", title: Text("Quit an app when its last window closes", bundle: .module),
                              caption: Text("Finder and menu bar apps are never quit.", bundle: .module),
                              isOn: Binding(get: { model.settings.quitWhenLastWindowCloses },
                                            set: { value in model.update { $0.quitWhenLastWindowCloses = value } }))
        }
        SettingsCard(Text("Quit protection", bundle: .module)) {
            SettingsToggleRow(symbol: "hand.raised", title: Text("Press ⌘Q twice to quit", bundle: .module),
                              caption: Text("Stops apps from closing by accident. Finder is never affected.", bundle: .module),
                              isOn: Binding(get: { model.settings.quitProtection },
                                            set: { value in model.update { $0.quitProtection = value } }))
            SettingsToggleRow(symbol: "xmark.square", title: Text("Press ⌘W twice to close a window", bundle: .module),
                              isOn: Binding(get: { model.settings.closeProtection },
                                            set: { value in model.update { $0.closeProtection = value } }))
            if model.settings.quitProtection || model.settings.closeProtection {
                Divider()
                Group {
                    if model.settings.protectedApps.isEmpty {
                        Text("Every app is protected. Add apps to protect only those.", bundle: .module)
                    } else {
                        Text("Only these apps are protected.", bundle: .module)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(model.settings.protectedApps, id: \.self) { bundleID in
                    SettingsRow(symbol: "app.dashed", title: Text(verbatim: bundleID)) {
                        Button(role: .destructive) {
                            model.update { $0.protectedApps.removeAll { $0 == bundleID } }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove app", bundle: .module))
                    }
                }
                Button { addProtectedApp() } label: {
                    Label { Text("Add app…", bundle: .module) } icon: { Image(systemName: "plus") }
                }
            }
        }
    }
}

extension WindowsSettingsView {
    fileprivate func addProtectedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.update { if !$0.protectedApps.contains(id) { $0.protectedApps.append(id) } }
    }
}
