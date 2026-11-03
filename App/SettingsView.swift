import SwiftUI
import SonaryCore
import SonaryUI

struct SettingsView: View {
    let model: AppModel
    @State private var selection: String? = "general"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag("general" as String?)
                Section("Modules") {
                    ForEach(model.registry.modules, id: \.id) { module in
                        Label {
                            Text(module.title)
                        } icon: {
                            Image(systemName: module.symbol)
                        }
                        .tag(module.id as String?)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, id != "general",
           let module = model.registry.modules.first(where: { $0.id == id }) {
            ModuleSettingsContainer(model: model, module: module)
        } else {
            GeneralSettings(model: model)
        }
    }
}

private struct ModuleSettingsContainer: View {
    let model: AppModel
    let module: any SonaryModule

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.registry.isEnabled(module.id) },
                    set: { on in Task { await model.registry.setEnabled(module.id, on) } }
                )) {
                    Text(module.title)
                }
                if let failure = model.registry.failures[module.id] {
                    Text(failure).foregroundStyle(.red)
                }
            }
            module.makeSettingsView()
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLogin.isEnabled },
                set: { model.launchAtLogin.set($0) }
            ))
            if let error = model.launchAtLogin.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            Button("Show onboarding again") {
                model.resetOnboarding()
                openWindow(id: "onboarding")
            }
        }
        .formStyle(.grouped)
    }
}
