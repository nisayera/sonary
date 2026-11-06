import SonaryCore
import SonaryUI
import SwiftUI

/// Settings window: a search field and a grouped sidebar (Sonary's own pages, then the modules by
/// category), and on the right one page per entry, each a header plus cards.
struct SettingsView: View {
    let model: AppModel
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarSearchField(query: $query)
                List(selection: Binding(get: { Optional(model.settingsPage) },
                                        set: { if let page = $0 { model.settingsPage = page } })) {
                    if isSearching {
                        searchResults
                    } else {
                        sections
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 198, ideal: 214, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 772, minHeight: 528)
        .tint(Color.sonaryAccent)
        .environment(\.sonaryAppearance, model.appearance)
    }

    // MARK: - Sidebar

    private struct Entry: Identifiable {
        let id: SettingsDestination
        let symbol: String
        let title: String
        var detail = ""
        var isOn: Bool?
    }

    private var essentials: [Entry] {
        [Entry(id: .general, symbol: "gearshape", title: String(localized: "General")),
         Entry(id: .features, symbol: "square.grid.2x2", title: String(localized: "Features")),
         Entry(id: .permissions, symbol: "lock.shield", title: String(localized: "Permissions")),
         Entry(id: .shortcuts, symbol: "keyboard", title: String(localized: "Shortcuts"))]
    }

    private var appEntries: [Entry] {
        [Entry(id: .updates, symbol: "arrow.down.circle", title: String(localized: "Updates")),
         Entry(id: .about, symbol: "info.circle", title: String(localized: "About"))]
    }

    private func moduleEntries(_ category: ModuleCategory) -> [Entry] {
        category.moduleIDs.compactMap { id in
            guard let module = model.registry.modules.first(where: { $0.id == id }) else { return nil }
            return Entry(id: .module(id), symbol: module.symbol, title: String(localized: module.title),
                         detail: ModuleInfo.summaryText(for: id), isOn: model.registry.isEnabled(id))
        }
    }

    @ViewBuilder
    private var sections: some View {
        Section("Essentials") {
            ForEach(essentials) { sidebarRow($0) }
        }
        ForEach(ModuleCategory.allCases, id: \.self) { category in
            Section(category.title) {
                ForEach(moduleEntries(category)) { sidebarRow($0) }
            }
        }
        Section("Sonary") {
            ForEach(appEntries) { sidebarRow($0) }
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var searchResults: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = essentials + ModuleCategory.allCases.flatMap(moduleEntries) + appEntries
        let found = all.filter { $0.title.localizedStandardContains(needle) || $0.detail.localizedStandardContains(needle) }
        if found.isEmpty {
            Text("No results").foregroundStyle(.secondary)
        } else {
            ForEach(found) { sidebarRow($0) }
        }
    }

    private func sidebarRow(_ entry: Entry) -> some View {
        HStack(spacing: 9) {
            Image(systemName: entry.symbol)
                .foregroundStyle(model.settingsPage == entry.id ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.sonaryAccent))
                .frame(width: 18)
            Text(verbatim: entry.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let isOn = entry.isOn {
                Circle()
                    .fill(isOn ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(isOn ? Text("On") : Text("Off"))
            }
        }
        .tag(entry.id)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch model.settingsPage {
        case .general: GeneralPage(model: model)
        case .features: FeaturesPage(model: model)
        case .permissions: PermissionsPage(model: model)
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

/// A search field that sits above the sidebar list. The system's sidebar search lets rows slide
/// under the field on macOS 26, so this one has a fixed place of its own.
private struct SidebarSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(text: $query, prompt: Text("Search settings")) { Text("Search settings") }
                .textFieldStyle(.plain)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
                        SettingsRow(symbol: "lock.shield", title: Text(permissionTitle(permission)),
                                    caption: Text("Asked for when you turn the module on.")) { EmptyView() }
                    }
                }
            }
            module.makeSettingsView()
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
