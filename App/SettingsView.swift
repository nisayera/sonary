import SonaryCore
import SonaryUI
import SwiftUI

private enum SettingsPageID: Hashable {
    case general
    case shortcuts
    case updates
    case about
    case module(String)
}

/// Settings window: sidebar with Sonary's own pages and one page per module; each page is a header plus cards.
struct SettingsView: View {
    let model: AppModel
    @State private var selection: SettingsPageID? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Sonary") {
                    sidebarRow(.general, symbol: "gearshape", title: Text("General"))
                    sidebarRow(.shortcuts, symbol: "keyboard", title: Text("Shortcuts"))
                    sidebarRow(.updates, symbol: "arrow.down.circle", title: Text("Updates"))
                    sidebarRow(.about, symbol: "info.circle", title: Text("About"))
                }
                Section("Modules") {
                    ForEach(model.registry.modules, id: \.id) { module in
                        sidebarRow(.module(module.id), symbol: module.symbol, title: Text(module.title),
                                   isOn: model.registry.isEnabled(module.id))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 214, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 520)
        .tint(Color.sonaryAccent)
        .environment(\.sonaryAppearance, model.appearance)
    }

    private func sidebarRow(_ id: SettingsPageID, symbol: String, title: Text, isOn: Bool? = nil) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(selection == id ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.sonaryAccent))
                .frame(width: 18)
            title
            Spacer(minLength: 4)
            if let isOn {
                Circle()
                    .fill(isOn ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(isOn ? Text("On") : Text("Off"))
            }
        }
        .tag(id)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general: GeneralPage(model: model)
        case .shortcuts: ShortcutsPage()
        case .updates: UpdatesPage(model: model)
        case .about: AboutPage()
        case let .module(id):
            if let module = model.registry.modules.first(where: { $0.id == id }) {
                ModulePage(model: model, module: module)
            } else {
                GeneralPage(model: model)
            }
        }
    }
}

private struct ModulePage: View {
    let model: AppModel
    let module: any SonaryModule

    var body: some View {
        SettingsPage {
            SettingsPageHeader(symbol: module.symbol, title: Text(module.title),
                               subtitle: Text(ModuleInfo.summary(for: module.id))) {
                Toggle(isOn: Binding(
                    get: { model.registry.isEnabled(module.id) },
                    set: { on in Task { await model.registry.setEnabled(module.id, on) } }
                )) { Text(module.title) }
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } content: {
            if let failure = model.registry.failures[module.id] {
                SettingsCard {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            if !module.requiredPermissions.isEmpty {
                SettingsCard(Text("Permissions")) {
                    ForEach(module.requiredPermissions, id: \.self) { permission in
                        SettingsRow(symbol: "lock.shield", title: Text(permissionName(permission)),
                                    caption: Text("Asked for when you turn the module on.")) { EmptyView() }
                    }
                }
            }
            module.makeSettingsView()
        }
    }

    private func permissionName(_ permission: SonaryPermission) -> LocalizedStringKey {
        switch permission {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen Recording"
        case .fullDiskAccess: "Full Disk Access"
        case .notifications: "Notifications"
        case .calendars: "Calendars"
        }
    }
}

private struct GeneralPage: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsPage {
            SettingsPageHeader(symbol: "gearshape", title: Text("General"),
                               subtitle: Text("How Sonary starts and behaves."))
        } content: {
            SettingsCard(Text("Startup")) {
                SettingsToggleRow(symbol: "power", title: Text("Open at login"),
                                  caption: model.launchAtLogin.errorMessage.map { Text($0) },
                                  isOn: Binding(get: { model.launchAtLogin.isEnabled },
                                                set: { model.launchAtLogin.set($0) }))
            }
            SettingsCard(Text("Appearance")) {
                SettingsRow(symbol: "square.on.square.dashed", title: Text("Panels and the island"),
                            caption: Text("How much of the desktop shows through.")) {
                    Picker(selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                        ForEach(SonaryAppearance.allCases, id: \.self) { Text(appearanceTitle($0)).tag($0) }
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 150)
                }
            }
            SettingsCard(Text("Introduction")) {
                SettingsRow(symbol: "hand.wave", title: Text("Welcome window"),
                            caption: Text("Explains Sonary and the permissions of your modules.")) {
                    Button("Show onboarding again") {
                        model.resetOnboarding()
                        openWindow(id: "onboarding")
                    }
                }
            }
        }
    }
}

private struct UpdatesPage: View {
    let model: AppModel

    var body: some View {
        SettingsPage {
            SettingsPageHeader(symbol: "arrow.down.circle", title: Text("Updates"),
                               subtitle: Text("Sonary updates itself from its GitHub releases."))
        } content: {
            SettingsCard {
                SettingsToggleRow(symbol: "clock.arrow.circlepath", title: Text("Check for updates automatically"),
                                  isOn: Binding(get: { model.updates.automaticallyChecks },
                                                set: { model.updates.setAutomaticallyChecks($0) }))
                Divider()
                SettingsRow(symbol: "arrow.down.circle", title: Text("Version"),
                            caption: Text(UpdateModel.versionString)) {
                    Button("Check for Updates…") { model.updates.checkForUpdates() }
                        .disabled(!model.updates.canCheckForUpdates)
                }
            }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        SettingsPage {
            SettingsPageHeader(symbol: "info.circle", title: Text("About"),
                               subtitle: Text("Your Mac's menu bar toolbox. Open source, modular, native for macOS 26."))
        } content: {
            SettingsCard {
                SettingsRow(symbol: "number", title: Text("Version"), caption: Text(UpdateModel.versionString)) {
                    EmptyView()
                }
                Divider()
                SettingsRow(symbol: "chevron.left.forwardslash.chevron.right", title: Text("Source code"),
                            caption: Text(verbatim: "github.com/nisayera/sonary")) {
                    if let url = URL(string: "https://github.com/nisayera/sonary") {
                        Link("Open", destination: url)
                    }
                }
                Divider()
                SettingsRow(symbol: "doc.text", title: Text("License"),
                            caption: Text(verbatim: "GNU GPL v3.0 or later")) {
                    EmptyView()
                }
            }
        }
    }
}

func appearanceTitle(_ appearance: SonaryAppearance) -> LocalizedStringKey {
    switch appearance {
    case .glass: "Glass"
    case .frosted: "Frosted"
    case .solid: "Solid"
    }
}
