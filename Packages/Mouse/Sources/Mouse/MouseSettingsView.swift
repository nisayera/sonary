import AppKit
import SonaryUI
import SwiftUI

private enum ActionChoice: String, CaseIterable, Identifiable {
    case system, none, back, forward, missionControl, appExpose, showDesktop, launchpad
    var id: String { rawValue }

    var action: ButtonAction? {
        switch self {
        case .system: nil
        case .none: ButtonAction.none
        case .back: .back
        case .forward: .forward
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .showDesktop: .showDesktop
        case .launchpad: .launchpad
        }
    }

    init(_ action: ButtonAction?) {
        switch action {
        case nil: self = .system
        case .some(.none): self = .none
        case .some(.back): self = .back
        case .some(.forward): self = .forward
        case .some(.missionControl): self = .missionControl
        case .some(.appExpose): self = .appExpose
        case .some(.showDesktop): self = .showDesktop
        case .some(.launchpad): self = .launchpad
        case .some(.keyboardShortcut): self = .system
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .system: "Default"
        case .none: "Do nothing"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Launchpad"
        }
    }
}

struct MouseSettingsView: View {
    let module: MouseModule

    var body: some View {
        SettingsCard(Text("Scrolling", bundle: .module)) {
            SettingsToggleRow(symbol: "arrow.up.and.down.text.horizontal",
                              title: Text("Linear scrolling", bundle: .module),
                              caption: Text("Every wheel step scrolls the same distance.", bundle: .module),
                              isOn: binding(\.linearScroll))
            if module.settings.linearScroll {
                SettingsRow(symbol: "list.number",
                            title: Text("Lines per wheel step: \(module.settings.scrollLinesPerStep)", bundle: .module)) {
                    Stepper(value: binding(\.scrollLinesPerStep), in: 1...20) { EmptyView() }
                        .labelsHidden()
                }
            }
            Divider()
            SettingsToggleRow(symbol: "water.waves", title: Text("Smooth scrolling", bundle: .module),
                              isOn: binding(\.smoothScroll))
            if module.settings.smoothScroll {
                SettingsRow(symbol: "slider.horizontal.3", title: Text("Smoothness", bundle: .module)) {
                    Slider(value: binding(\.smoothness), in: 0...1).frame(width: 160)
                }
            }
            Divider()
            SettingsToggleRow(symbol: "arrow.up.arrow.down", title: Text("Reverse mouse wheel direction", bundle: .module),
                              caption: Text("Trackpads and Magic Mouse are not changed.", bundle: .module),
                              isOn: binding(\.reverseScroll))
            Divider()
            SettingsRow(symbol: "arrow.left.and.right",
                        title: Text("Scroll sideways while holding", bundle: .module)) {
                Picker(selection: binding(\.horizontalScrollModifier)) {
                    ForEach(ScrollModifier.allCases, id: \.self) { modifier in
                        Text(modifierTitle(modifier), bundle: .module).tag(modifier)
                    }
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 150)
            }
        }

        SettingsCard(Text("Pointer", bundle: .module)) {
            SettingsToggleRow(symbol: "cursorarrow.motionlines",
                              title: Text("Turn off pointer acceleration", bundle: .module),
                              caption: Text("The original setting is restored when the module is turned off or Sonary quits.", bundle: .module),
                              isOn: binding(\.disableAcceleration))
        }

        SettingsCard(Text("Extra buttons", bundle: .module)) {
            ForEach([3, 4, 5], id: \.self) { button in
                SettingsRow(symbol: "computermouse", title: Text("Button \(button + 1)", bundle: .module)) {
                    Picker(selection: mappingBinding(for: button)) {
                        ForEach(ActionChoice.allCases) { choice in
                            Text(choice.label, bundle: .module).tag(choice)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }
        }

        SettingsCard(Text("Click filter", bundle: .module)) {
            SettingsRow(symbol: "hand.tap",
                        title: module.settings.clickFilterMilliseconds == 0
                            ? Text("Click filter: off", bundle: .module)
                            : Text("Ignore repeat clicks within \(module.settings.clickFilterMilliseconds) ms", bundle: .module),
                        caption: Text("Helps with worn mouse buttons that double-click by themselves.", bundle: .module)) {
                Stepper(value: binding(\.clickFilterMilliseconds), in: 0...500, step: 10) { EmptyView() }
                    .labelsHidden()
            }
        }

        SettingsCard(Text("Exceptions", bundle: .module)) {
            Text("Turn Sonary's mouse changes off while one of these apps is in front.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ForEach(module.settings.appOverrides.keys.sorted(), id: \.self) { bundleID in
                SettingsRow(symbol: "app.dashed", title: Text(appName(for: bundleID))) {
                    Toggle(isOn: Binding(
                        get: { module.settings.appOverrides[bundleID]?.disabled ?? false },
                        set: { on in module.update { $0.appOverrides[bundleID, default: AppOverride()].disabled = on } }
                    )) { EmptyView() }
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Button(role: .destructive) {
                        module.update { _ = $0.appOverrides.removeValue(forKey: bundleID) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Remove exception", bundle: .module))
                }
            }
            Button {
                addApp()
            } label: {
                Label { Text("Add app…", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MouseSettings, Value>) -> Binding<Value> {
        Binding(
            get: { module.settings[keyPath: keyPath] },
            set: { value in module.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func mappingBinding(for button: Int) -> Binding<ActionChoice> {
        Binding(
            get: { ActionChoice(action(forButton: button, in: module.settings.buttonMappings)) },
            set: { choice in
                module.update { settings in
                    settings.buttonMappings.removeAll { $0.button == button }
                    if let action = choice.action {
                        settings.buttonMappings.append(ButtonMapping(button: button, action: action))
                    }
                }
            }
        )
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        module.update { $0.appOverrides[id, default: AppOverride()].disabled = true }
    }
}

func modifierTitle(_ modifier: ScrollModifier) -> LocalizedStringKey {
    switch modifier {
    case .none: "Off"
    case .shift: "Shift"
    case .control: "Control"
    case .option: "Option"
    case .command: "Command"
    }
}
