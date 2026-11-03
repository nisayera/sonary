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
        SettingsCard(Text("Quit protection", bundle: .module)) {
            SettingsToggleRow(symbol: "hand.raised", title: Text("Press ⌘Q twice to quit", bundle: .module),
                              caption: Text("Stops apps from closing by accident. Finder is never affected.", bundle: .module),
                              isOn: Binding(get: { model.settings.quitProtection },
                                            set: { value in model.update { $0.quitProtection = value } }))
        }
    }
}
