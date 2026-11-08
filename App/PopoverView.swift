import AppKit
import SonaryCore
import SonaryUI
import SwiftUI

/// The menu bar panel: the Sonary mark, icon tabs (the module overview plus one per running
/// module), the section, and Settings and Quit at the bottom.
struct PopoverView: View {
    let model: AppModel
    @State private var tab: PanelTab
    @State private var contentHeight: CGFloat = 320
    /// The overview's open categories, as a comma-separated list; each opens on its own.
    @AppStorage("panel.overview.open") private var openCategory = "system"
    @Environment(\.openSettings) private var openSettings

    init(model: AppModel, initialTab: PanelTab = .overview) {
        self.model = model
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        let available = model.registry.modules.filter {
            model.registry.isEnabled($0.id) && $0.makePopoverView() != nil
        }
        let order = orderedPanelTabs(available: available.map(\.id), order: model.panelTabOrder,
                                     hidden: model.hiddenPanelTabs)
        let panelModules = order.compactMap { id in available.first { $0.id == id } }
        let current = currentTab(in: panelModules)
        VStack(alignment: .leading, spacing: PanelMetrics.spacing) {
            header
            if let version = model.updatedToVersion {
                whatsNew(version)
            }
            IconTabBar(tabs: tabs(for: panelModules), selection: Binding(get: { current }, set: { tab = $0 }))
            sectionTitle(for: current, panelModules: panelModules)
                .padding(.horizontal, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: PanelMetrics.spacing) {
                    content(for: current, panelModules: panelModules)
                }
                .controlSize(.small)
                .frame(width: PanelMetrics.contentWidth, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
            }
            // Sections fold instead of scrolling. This only guards a screen too small for even one
            // open section, and never shows a scroller: a visible one took width from the content
            // and pushed it sideways when a mouse was attached.
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 40), maxContentHeight))
            footer(for: current)
        }
        .padding(PanelMetrics.padding)
        .frame(width: PanelMetrics.width)
        .background(PanelSurfaceBackground())
        .environment(\.sonarySurface, .panel)
        .environment(\.sonaryAppearance, model.appearance)
        .tint(Color.sonaryAccent)
    }

    /// As tall as the screen allows below the menu bar, less the header, tabs and footer.
    private var maxContentHeight: CGFloat {
        max(PanelMetrics.maxContentHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 230)
    }

    private func currentTab(in panelModules: [any SonaryModule]) -> PanelTab {
        if case let .module(id) = tab, !panelModules.contains(where: { $0.id == id }) { return .overview }
        return tab
    }

    private func tabs(for panelModules: [any SonaryModule]) -> [IconTab<PanelTab>] {
        [IconTab(id: .overview, symbol: "square.grid.2x2", title: Text("Overview"))]
            + panelModules.map { IconTab(id: .module($0.id), symbol: $0.symbol, title: Text($0.title)) }
    }

    // MARK: - Header and section title

    /// The mark on its badge, the date and the time: the panel opens with something worth
    /// a glance even before a tab is picked.
    private var header: some View {
        HStack(spacing: 10) {
            // The app's own icon, not the menu bar mark.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            if model.panelOptions.showsClock {
                TimelineView(.periodic(from: Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now,
                                       by: model.panelOptions.clockSeconds ? 1 : 60)) { context in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: "Sonary").font(.system(size: 13, weight: .bold))
                            Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(context.date, format: model.panelOptions.clockSeconds
                             ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
                            .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
            } else {
                Text(verbatim: "Sonary").font(.system(size: 13, weight: .bold))
                Spacer()
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func sectionTitle(for tab: PanelTab, panelModules: [any SonaryModule]) -> some View {
        switch tab {
        case .overview:
            let running = model.registry.modules.filter { model.registry.isEnabled($0.id) }
            // With live values the overview opens on them; the count says how many modules run.
            let glancing = model.panelOptions.showsGlance && running.contains { !$0.status.isEmpty }
            PanelSectionTitle(glancing ? Text("At a glance") : Text("Modules")) {
                count(running.count, of: model.registry.modules.count)
            }
        case let .module(id):
            if let module = panelModules.first(where: { $0.id == id }) {
                PanelSectionTitle(Text(module.title)) {
                    settingsButton(.module(id))
                }
            }
        }
    }

    /// Shown once after an update: what version this is, and a way to its release notes.
    private func whatsNew(_ version: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Color.sonaryAccent)
            Text("Updated to \(version)").font(.system(size: 11, weight: .medium))
            Spacer()
            Button {
                if let url = URL(string: "https://github.com/nisayera/sonary/releases/tag/v\(version)") {
                    NSWorkspace.shared.open(url)
                }
                model.dismissWhatsNew()
            } label: { Text("What's new") }
            Button { model.dismissWhatsNew() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Dismiss"))
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .panelCard(padded: false)
    }

    private func count(_ on: Int, of total: Int) -> some View {
        Text(verbatim: "\(on)/\(total)")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.sonaryAccent)
    }

    private func settingsButton(_ page: SettingsDestination) -> some View {
        Button {
            openSettingsPage(page)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Settings…"))
        .accessibilityLabel(Text("Settings…"))
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for tab: PanelTab, panelModules: [any SonaryModule]) -> some View {
        switch tab {
        case .overview:
            glance
            ForEach(ModuleCategory.allCases, id: \.self) { category in
                let members = modules(in: category)
                if !members.isEmpty {
                    PanelDisclosure(symbol: category.symbol, title: Text(category.title),
                                    isExpanded: $openCategory.opens(category.storageID)) {
                        count(members.filter { model.registry.isEnabled($0.id) }.count, of: members.count)
                    } content: {
                        PanelGroup {
                            ForEach(members, id: \.id) { module in
                                moduleRow(module)
                            }
                        }
                    }
                }
            }
        case let .module(id):
            if let module = panelModules.first(where: { $0.id == id }), let view = module.makePopoverView() {
                view
            }
        }
    }

    /// The live values of every running module, two to a row.
    @ViewBuilder
    private var glance: some View {
        let options = model.panelOptions
        let values = model.registry.modules.filter { model.registry.isEnabled($0.id) }.flatMap { module in
            module.status.filter { !options.hiddenGlance.contains(glanceKey(module.id, $0.id)) }
        }
        if options.showsGlance, !values.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(2, min(3, options.glanceColumns))),
                      spacing: 8) {
                ForEach(Array(values.prefix(options.glanceLimit).enumerated()), id: \.offset) { _, status in
                    GlanceTile(symbol: status.symbol, title: Text(verbatim: status.title), value: status.value,
                               fraction: status.fraction, tint: statusTint(status.level))
                }
            }
        }
    }

    private func modules(in category: ModuleCategory) -> [any SonaryModule] {
        category.moduleIDs.compactMap { id in model.registry.modules.first { $0.id == id } }
    }

    private func moduleRow(_ module: any SonaryModule) -> some View {
        let failure = model.registry.failures[module.id]
        let isOn = model.registry.isEnabled(module.id)
        return PanelRow(symbol: module.symbol, title: Text(module.title),
                        caption: failure.map { Text($0) }
                            ?? (isOn && model.panelOptions.showsStatusLines ? statusLine(module) : nil),
                        isActive: model.registry.isEnabled(module.id),
                        needsAttention: failure != nil) {
            Toggle(isOn: Binding(
                get: { model.registry.isEnabled(module.id) },
                set: { on in Task { await model.registry.setEnabled(module.id, on) } }
            )) { Text(module.title) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .help(Text(ModuleInfo.summary(for: module.id)))
    }

    // MARK: - Footer

    private func footer(for tab: PanelTab) -> some View {
        HStack(spacing: 8) {
            Button {
                if case let .module(id) = tab {
                    openSettingsPage(.module(id))
                } else {
                    openSettingsPage(model.settingsPage)
                }
            } label: {
                Label { Text("Settings…") } icon: { Image(systemName: "gearshape") }
            }
            .keyboardShortcut(",")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label { Text("Quit Sonary") } icon: { Image(systemName: "power") }
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(PanelFooterButtonStyle())
    }

    private func openSettingsPage(_ page: SettingsDestination) {
        model.settingsPage = page
        NSApp.activate()
        openSettings()
    }
}

/// The colour of a live value: the accent while it is fine, orange or red when it is not.
func statusTint(_ level: ModuleStatus.Level) -> Color {
    switch level {
    case .normal: .sonaryAccent
    case .warning: .orange
    case .critical: .red
    }
}

/// A module's first live values as one line, such as "CPU 13 % · Memory 64 %".
@MainActor
func statusLine(_ module: any SonaryModule) -> Text? {
    let values = module.status.prefix(2)
    guard !values.isEmpty else { return nil }
    return Text(verbatim: values.map { "\($0.title) \($0.value)" }.joined(separator: " · "))
}
