import AppKit
import SonaryCore
import SonaryUI
import SwiftUI

private enum PanelTab: Hashable {
    case overview
    case module(String)
}

/// The menu bar panel: header, icon tabs (overview plus one per active module), content and footer.
struct PopoverView: View {
    let model: AppModel
    @State private var tab: PanelTab = .overview

    var body: some View {
        let panelModules = model.registry.modules.filter {
            model.registry.isEnabled($0.id) && $0.makePopoverView() != nil
        }
        let current = currentTab(in: panelModules)
        VStack(spacing: 10) {
            header
            IconTabBar(tabs: tabs(for: panelModules), selection: Binding(get: { current }, set: { tab = $0 }))
            ScrollView {
                VStack(spacing: Spacing.s) {
                    content(for: current, panelModules: panelModules)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: 430)
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Sonary").font(.headline)
                Text(UpdateModel.versionString).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func content(for tab: PanelTab, panelModules: [any SonaryModule]) -> some View {
        switch tab {
        case .overview:
            SettingsCard(Text("Modules")) {
                ForEach(model.registry.modules, id: \.id) { module in
                    SettingsRow(symbol: module.symbol, title: Text(module.title),
                                caption: model.registry.failures[module.id].map { Text($0) }) {
                        Toggle(isOn: Binding(
                            get: { model.registry.isEnabled(module.id) },
                            set: { on in Task { await model.registry.setEnabled(module.id, on) } }
                        )) { Text(module.title) }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }
            if panelModules.isEmpty {
                Text("Turn on a module to see it here as its own tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .module(id):
            if let module = panelModules.first(where: { $0.id == id }), let view = module.makePopoverView() {
                view
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            .help(Text("Settings…"))
            Button {
                model.updates.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
            .disabled(!model.updates.canCheckForUpdates)
            .help(Text("Check for Updates…"))
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Sonary", systemImage: "power")
            }
            .keyboardShortcut("q")
            .help(Text("Quit Sonary"))
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
    }
}
