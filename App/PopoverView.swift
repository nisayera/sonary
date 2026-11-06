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
    @Environment(\.openSettings) private var openSettings

    init(model: AppModel, initialTab: PanelTab = .overview) {
        self.model = model
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        let panelModules = model.registry.modules.filter {
            model.registry.isEnabled($0.id) && $0.makePopoverView() != nil
        }
        let current = currentTab(in: panelModules)
        VStack(alignment: .leading, spacing: PanelMetrics.spacing) {
            header
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
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 40), PanelMetrics.maxContentHeight))
            footer(for: current)
        }
        .padding(PanelMetrics.padding)
        .frame(width: PanelMetrics.width)
        .background(PanelSurfaceBackground())
        .environment(\.sonarySurface, .panel)
        .environment(\.sonaryAppearance, model.appearance)
        .tint(Color.sonaryAccent)
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

    private var header: some View {
        SonaryMark()
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func sectionTitle(for tab: PanelTab, panelModules: [any SonaryModule]) -> some View {
        switch tab {
        case .overview:
            let on = model.registry.modules.filter { model.registry.isEnabled($0.id) }.count
            PanelSectionTitle(Text("Modules")) {
                count(on, of: model.registry.modules.count)
            }
        case let .module(id):
            if let module = panelModules.first(where: { $0.id == id }) {
                PanelSectionTitle(Text(module.title)) {
                    settingsButton(.module(id))
                }
            }
        }
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
            ForEach(ModuleCategory.allCases, id: \.self) { category in
                let members = modules(in: category)
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        PanelSectionTitle(Text(category.title)) {
                            count(members.filter { model.registry.isEnabled($0.id) }.count, of: members.count)
                        }
                        .padding(.horizontal, 2)
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

    private func modules(in category: ModuleCategory) -> [any SonaryModule] {
        category.moduleIDs.compactMap { id in model.registry.modules.first { $0.id == id } }
    }

    private func moduleRow(_ module: any SonaryModule) -> some View {
        let failure = model.registry.failures[module.id]
        return PanelRow(symbol: module.symbol, title: Text(module.title),
                        caption: failure.map { Text($0) },
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
