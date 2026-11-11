import SonaryCore
import SonaryUI
import SwiftUI

/// Settings window: a search field and a grouped sidebar (Sonary's own pages, then the modules by
/// category), and on the right one page per entry, each a header plus cards.
struct SettingsView: View {
    let model: AppModel
    @State private var query = ""
    /// Every option's text, read once when the window opens.
    @State private var optionIndex: [(moduleID: String, text: String)] = []

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
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .frame(minWidth: 772, minHeight: 528)
        .task { optionIndex = model.searchableOptions() }
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
        let options = optionIndex.filter { $0.text.localizedStandardContains(needle) }.prefix(30)
        if found.isEmpty && options.isEmpty {
            Text("No results").foregroundStyle(.secondary)
        } else {
            ForEach(found) { sidebarRow($0) }
            if !options.isEmpty {
                Section("Options") {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        optionRow(option)
                    }
                }
            }
        }
    }

    /// An option found by its text: the text, and the module page it is on.
    private func optionRow(_ option: (moduleID: String, text: String)) -> some View {
        let module = model.registry.modules.first { $0.id == option.moduleID }
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: option.text).lineLimit(2)
            if let module {
                Text(module.title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tag(SettingsDestination.module(option.moduleID))
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
        case .shortcuts: AllShortcutsPage()
        case .updates: UpdatesPage(model: model)
        case .about: AboutPage()
        case let .module(id):
            if let engine = model.registry.modules.first(where: { $0.id == id }) as? EngineModule {
                EnginePage(model: model, module: engine)
            } else if let module = model.registry.modules.first(where: { $0.id == id }) {
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
            if model.registry.isEnabled(module.id), !module.status.isEmpty {
                SettingsCard(Text("Right now")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(module.status) { status in
                            GlanceTile(symbol: status.symbol, title: Text(verbatim: status.title), value: status.value,
                                       fraction: status.fraction, tint: statusTint(status.level))
                        }
                    }
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

    private func optionBinding<Value>(_ keyPath: WritableKeyPath<PanelOptions, Value>) -> Binding<Value> {
        Binding(get: { model.panelOptions[keyPath: keyPath] },
                set: { value in model.updatePanelOptions { $0[keyPath: keyPath] = value } })
    }
    @Environment(\.openWindow) private var openWindow
    @AppStorage(colorSchemeKey) private var colorScheme = "system"
    @AppStorage(menuBarSymbolKey) private var menuBarSymbol = ""

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
                SettingsRow(symbol: "circle.lefthalf.filled", title: Text("Light or dark")) {
                    Picker(selection: $colorScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    } label: { EmptyView() }
                        .settingsControl()
                        .onChange(of: colorScheme) { _, choice in applyColorScheme(choice) }
                }
                SettingsRow(symbol: "menubar.arrow.up.rectangle", title: Text("Menu bar icon")) {
                    Picker(selection: $menuBarSymbol) {
                        ForEach(menuBarSymbolChoices, id: \.self) { name in
                            if name.isEmpty {
                                Text(verbatim: "Sonary").tag(name)
                            } else {
                                Image(systemName: name).tag(name)
                            }
                        }
                    } label: { EmptyView() }
                        .settingsControl()
                }
                SettingsRow(symbol: "paintpalette", title: Text("Accent colour"),
                            caption: Text("Used for icons, tabs, rings and bars everywhere in Sonary.")) {
                    AccentPicker(selection: SonaryTheme.shared.accent) { SonaryTheme.shared.setAccent($0) }
                    ColorPicker(selection: Binding(get: { Color.sonaryAccent }, set: { SonaryTheme.shared.setCustom($0) }),
                                supportsOpacity: false) { Text("Custom colour") }
                        .labelsHidden()
                        .help(Text("Custom colour"))
                }
                SettingsRow(symbol: "square.on.square.dashed", title: Text("Panels and the island"),
                            caption: Text("How much of the desktop shows through.")) {
                    Picker(selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                        ForEach(SonaryAppearance.allCases, id: \.self) { Text(appearanceTitle($0)).tag($0) }
                    } label: { EmptyView() }
                        .settingsControl()
                }
            }
            SettingsCard(Text("Panel header and overview")) {
                SettingsToggleRow(symbol: "clock", title: Text("Show the date and time"),
                                  isOn: optionBinding(\.showsClock))
                if model.panelOptions.showsClock {
                    SettingsToggleRow(symbol: "timer", title: Text("With seconds"), isOn: optionBinding(\.clockSeconds))
                }
                SettingsToggleRow(symbol: "square.grid.2x2", title: Text("Show live values at the top"),
                                  caption: Text("Tiles with the values of the running modules, such as CPU, volume or the track playing."),
                                  isOn: optionBinding(\.showsGlance))
                if model.panelOptions.showsGlance {
                    SettingsRow(symbol: "rectangle.split.3x1", title: Text("Tiles per row")) {
                        Picker(selection: optionBinding(\.glanceColumns)) {
                            Text(verbatim: "2").tag(2)
                            Text(verbatim: "3").tag(3)
                        } label: { EmptyView() }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 90)
                    }
                    SettingsRow(symbol: "number", title: Text("At most")) {
                        Stepper(value: optionBinding(\.glanceLimit), in: 2...12, step: 1) {
                            Text("\(model.panelOptions.glanceLimit) tiles")
                        }
                    }
                    GlanceValuePicker(model: model)
                }
                SettingsToggleRow(symbol: "text.below.photo", title: Text("Live values under each module"),
                                  caption: Text("A second line in the module list with each module's values, such as its CPU load."),
                                  isOn: optionBinding(\.showsStatusLines))
            }
            SettingsCard(Text("Menu panel")) {
                Text("Which tabs the panel shows, and in what order. Home always comes first.")
                    .font(.caption).foregroundStyle(.secondary)
                let ids = orderedPanelTabs(available: PanelArea.allCases.map(\.id), order: model.panelTabOrder, hidden: [])
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    if let area = PanelArea(rawValue: id) {
                        SettingsRow(symbol: area.symbol, title: Text(area.title)) {
                            Button { model.setPanelTabOrder(movedUp(ids, at: index)) } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                .accessibilityLabel(Text("Move up"))
                            Toggle(isOn: Binding(get: { !model.hiddenPanelTabs.contains(id) },
                                                 set: { model.setPanelTab(id, hidden: !$0) })) { Text(area.title) }
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }
            SettingsCard(Text("Your data")) {
                SettingsRow(symbol: "square.and.arrow.up", title: Text("Export settings"),
                            caption: Text("A file with every choice you made, to take to another Mac.")) {
                    Button("Export…") { model.exportSettings() }
                }
                SettingsRow(symbol: "square.and.arrow.down", title: Text("Import settings"),
                            caption: Text("Replaces your settings with the ones in the file and restarts Sonary.")) {
                    Button("Import…") { model.importSettings() }
                }
                SettingsRow(symbol: "trash", title: Text("Remove all data"),
                            caption: Text("Puts back what Sonary changed, deletes its settings and data, and quits.")) {
                    Button("Remove…", role: .destructive) { model.removeAllData() }
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
                SettingsRow(symbol: "chevron.left.forwardslash.chevron.right", title: Text("Source code"),
                            caption: Text(verbatim: "github.com/nisayera/sonary")) {
                    if let url = URL(string: "https://github.com/nisayera/sonary") {
                        Link("Open", destination: url)
                    }
                }
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

/// Every live value the running modules offer, each with a switch for the overview.
private struct GlanceValuePicker: View {
    let model: AppModel

    var body: some View {
        let running = model.registry.modules.filter { model.registry.isEnabled($0.id) }
        let entries = running.flatMap { module in module.status.map { (module: module, status: $0) } }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Values on the overview").font(.callout.weight(.medium))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2), alignment: .leading,
                          spacing: 6) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        let key = glanceKey(entry.module.id, entry.status.id)
                        Toggle(isOn: Binding(
                            get: { !model.panelOptions.hiddenGlance.contains(key) },
                            set: { on in
                                model.updatePanelOptions { options in
                                    options.hiddenGlance.removeAll { $0 == key }
                                    if !on { options.hiddenGlance.append(key) }
                                }
                            }
                        )) {
                            Label { Text(verbatim: entry.status.title) } icon: { Image(systemName: entry.status.symbol) }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                Text("Values of modules that are off appear once they run.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
