import SonaryCore
import SonaryUI
import SwiftUI
import Vorssaint

/// The settings page of an engine module: Sonary's header and switch, the module's panes to pick
/// from, and below them the pane itself. A pane is Vorssaint's and scrolls on its own, so it gets
/// the rest of the page instead of sitting inside Sonary's scrolling page.
struct EnginePage: View {
    let model: AppModel
    let module: EngineModule

    var body: some View {
        // Read here, so the page is drawn again with the new colour when the accent changes.
        let _ = SonaryEngine.setAccent(Color.sonaryAccent)
        let panes = module.panes
        let chosen = model.enginePanes[module.id]
        let current = chosen.flatMap { panes.contains($0) ? $0 : nil } ?? panes.first ?? ""
        // A pane asked for its ideal size answers with its whole content, and the window's detail
        // column asks. The reader answers with next to nothing and lays the page out in the space
        // there really is, as Vorssaint's own settings window does.
        GeometryReader { geometry in
            page(panes: panes, current: current, width: geometry.size.width)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped()
        }
    }

    private func page(panes: [String], current: String, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsPageHeader(symbol: module.symbol, title: Text(module.title),
                                   subtitle: Text(ModuleInfo.summary(for: module.id))) {
                    Toggle(isOn: Binding(
                        get: { model.registry.isEnabled(module.id) },
                        set: { on in Task { await model.registry.setEnabled(module.id, on) } }
                    )) { Text(module.title) }
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if let failure = model.registry.failures[module.id] {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if module.isLive, panes.count > 1 {
                    // Not a segmented control: seven panes are wider than the window, and a
                    // control that cannot shrink pushed the whole page out of it.
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(panes, id: \.self) { pane in
                                Button {
                                    model.enginePanes[module.id] = pane
                                } label: {
                                    Text(EnginePaneInfo.title(pane))
                                        .font(.system(size: 12, weight: pane == current ? .semibold : .regular))
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .foregroundStyle(pane == current ? Color.white : Color.primary)
                                        .background(pane == current ? Color.sonaryAccent : Color.primary.opacity(0.08),
                                                    in: Capsule())
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(pane == current ? .isSelected : [])
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .frame(width: width, alignment: .leading)
            Divider()
            if module.isLive {
                SonaryEngine.settingsView(pane: current)
                    .id(current)
                    .tint(Color.sonaryAccent)
                    .frame(width: width, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                VStack(spacing: 10) {
                    IconBadge(symbol: module.symbol, isActive: false, size: 40)
                    Text("Turn the module on to see its settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The shortcuts of the features, and Sonary's own next to them.
struct AllShortcutsPage: View {
    @State private var showsOwn = false

    var body: some View {
        GeometryReader { geometry in
            page.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            Picker(selection: $showsOwn) {
                Text("Features").tag(false)
                Text(verbatim: "Sonary").tag(true)
            } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider()
            if showsOwn {
                ShortcutsPage()
            } else {
                SonaryEngine.shortcutsView()
                    .tint(Color.sonaryAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}
