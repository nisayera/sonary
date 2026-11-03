import SonaryUI
import SwiftUI

private enum ToolsSection: String, CaseIterable, Identifiable {
    case tools, toggles, scratchpad, snippets
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .tools: "Tools"
        case .toggles: "Toggles"
        case .scratchpad: "Scratchpad"
        case .snippets: "Snippets"
        }
    }
}

struct ToolsPopoverView: View {
    let model: ToolsModel
    @State private var section: ToolsSection = .tools

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker(selection: $section) {
                ForEach(ToolsSection.allCases) { Text($0.title, bundle: .module).tag($0) }
            } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
            switch section {
            case .tools: toolsView
            case .toggles: togglesView
            case .scratchpad:
                TextEditor(text: Binding(get: { model.settings.scratchpad },
                                         set: { value in model.update { $0.scratchpad = value } }))
                    .font(.body)
                    .frame(height: 300)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .snippets: snippetsView
            }
            if let result = model.lastResult {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var toolsView: some View {
        VStack(spacing: 6) {
            tool("magnifyingglass", "Command bar", "⌥Space") { model.showCommandBar() }
            tool("text.viewfinder", "Copy text from screen", "⌃⌥T") { model.recognizeText() }
            tool("eyedropper", "Pick a color", "⌃⌥P") { model.pickColor() }
            tool("camera.viewfinder", "Screenshot to clipboard", "⌃⌥S") { model.screenshotToClipboard() }
            tool("circle.grid.cross", "Radial menu", "⌃⌥R") { model.showRadialMenu() }
        }
    }

    private var togglesView: some View {
        VStack(spacing: 6) {
            ForEach(quickToggleActions) { action in
                Button { model.run(action) } label: {
                    SettingsRow(symbol: action.symbol, title: Text(quickActionTitle(action), bundle: .module)) {
                        EmptyView()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Dark mode and the Trash ask once for permission to control the system.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tool(_ symbol: String, _ title: LocalizedStringKey, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(symbol: symbol, title: Text(title, bundle: .module)) {
                Text(verbatim: shortcut).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var snippetsView: some View {
        VStack(spacing: 6) {
            ForEach(model.settings.snippets) { snippet in
                Button { model.insert(snippet) } label: {
                    SettingsRow(symbol: "text.quote", title: Text(snippet.title),
                                caption: Text(snippet.text).font(.caption)) { EmptyView() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Edit snippets in Sonary's settings.", bundle: .module).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ToolsSettingsView: View {
    let model: ToolsModel

    var body: some View {
        SettingsCard(Text("Shortcuts", bundle: .module)) {
            SettingsToggleRow(symbol: "keyboard", title: Text("Keyboard shortcuts", bundle: .module),
                              caption: Text("⌥Space command bar, ⌃⌥T text from screen, ⌃⌥P color picker, ⌃⌥S screenshot.", bundle: .module),
                              isOn: Binding(get: { model.settings.shortcuts }, set: { value in model.update { $0.shortcuts = value } }))
        }
        SettingsCard(Text("Radial menu", bundle: .module)) {
            Text("⌃⌥R opens a ring of actions around the pointer. Pick which ones it holds, up to eight.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ForEach(QuickAction.allCases) { action in
                SettingsToggleRow(symbol: action.symbol, title: Text(quickActionTitle(action), bundle: .module),
                                  isOn: Binding(
                                      get: { model.settings.radialActions.contains(action) },
                                      set: { on in
                                          model.update { settings in
                                              settings.radialActions.removeAll { $0 == action }
                                              if on {
                                                  settings.radialActions = QuickAction.allCases.filter {
                                                      $0 == action || settings.radialActions.contains($0)
                                                  }
                                              }
                                          }
                                      }))
            }
        }
        SettingsCard(Text("Snippets", bundle: .module)) {
            Text("Placeholders: {date}, {time} and {clipboard}.", bundle: .module).font(.caption).foregroundStyle(.secondary)
            ForEach(model.settings.snippets) { snippet in
                HStack(alignment: .top) {
                    VStack(spacing: 4) {
                        TextField(text: binding(snippet.id, \.title)) { Text("Title", bundle: .module) }
                        TextField(text: binding(snippet.id, \.text), axis: .vertical) { Text("Text", bundle: .module) }
                            .lineLimit(1...4)
                    }
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { model.removeSnippet(snippet.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove snippet", bundle: .module))
                }
            }
            Button { model.addSnippet() } label: {
                Label { Text("Add snippet", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        }
        SettingsCard(Text("Permissions", bundle: .module)) {
            Text("Screenshots and text from screen ask once for the Screen Recording permission.", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<Snippet, String>) -> Binding<String> {
        Binding(
            get: { model.settings.snippets.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { value in
                model.update { settings in
                    if let index = settings.snippets.firstIndex(where: { $0.id == id }) {
                        settings.snippets[index][keyPath: keyPath] = value
                    }
                }
            }
        )
    }
}
