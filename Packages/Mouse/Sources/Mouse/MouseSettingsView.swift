import AppKit
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
        Section {
            Toggle(isOn: binding(\.linearScroll)) { Text("Linear scrolling", bundle: .module) }
            if module.settings.linearScroll {
                Stepper(value: binding(\.scrollLinesPerStep), in: 1...20) {
                    Text("Lines per wheel step: \(module.settings.scrollLinesPerStep)", bundle: .module)
                }
            }
            Toggle(isOn: binding(\.smoothScroll)) { Text("Smooth scrolling", bundle: .module) }
            if module.settings.smoothScroll {
                LabeledContent {
                    Slider(value: binding(\.smoothness), in: 0...1)
                } label: {
                    Text("Smoothness", bundle: .module)
                }
            }
            Toggle(isOn: binding(\.reverseScroll)) { Text("Reverse mouse wheel direction", bundle: .module) }
        } header: {
            Text("Scrolling", bundle: .module)
        } footer: {
            Text("Trackpads and Magic Mouse are not changed.", bundle: .module)
        }

        Section {
            Toggle(isOn: binding(\.disableAcceleration)) { Text("Turn off pointer acceleration", bundle: .module) }
        } header: {
            Text("Pointer", bundle: .module)
        } footer: {
            Text("The original setting is restored when the module is turned off or Sonary quits.", bundle: .module)
        }

        Section {
            ForEach([3, 4, 5], id: \.self) { button in
                Picker(selection: mappingBinding(for: button)) {
                    ForEach(ActionChoice.allCases) { choice in
                        Text(choice.label, bundle: .module).tag(choice)
                    }
                } label: {
                    Text("Button \(button + 1)", bundle: .module)
                }
            }
        } header: {
            Text("Extra buttons", bundle: .module)
        }

        Section {
            Stepper(value: binding(\.clickFilterMilliseconds), in: 0...500, step: 10) {
                if module.settings.clickFilterMilliseconds == 0 {
                    Text("Click filter: off", bundle: .module)
                } else {
                    Text("Ignore repeat clicks within \(module.settings.clickFilterMilliseconds) ms", bundle: .module)
                }
            }
        } header: {
            Text("Click filter", bundle: .module)
        }

        Section {
            ForEach(module.settings.appOverrides.keys.sorted(), id: \.self) { bundleID in
                HStack {
                    Toggle(isOn: Binding(
                        get: { module.settings.appOverrides[bundleID]?.disabled ?? false },
                        set: { on in module.update { $0.appOverrides[bundleID, default: AppOverride()].disabled = on } }
                    )) {
                        Text(appName(for: bundleID))
                    }
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
                Text("Add app…", bundle: .module)
            }
        } header: {
            Text("Exceptions", bundle: .module)
        } footer: {
            Text("Turn Sonary's mouse changes off while one of these apps is in front.", bundle: .module)
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
