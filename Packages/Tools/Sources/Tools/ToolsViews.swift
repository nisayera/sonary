import AppKit
import SonaryUI
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var previewingMarkdown = false
    @State private var convertingImages = false

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
            case .scratchpad: scratchpadView
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
            tool("pin", "Pin a screenshot", "") { model.pinScreenshot() }
            tool("web.camera", "Camera mirror", "") { model.toggleCamera() }
            tool(model.isRecording ? "stop.circle" : "record.circle",
                 model.isRecording ? "Stop recording" : "Record the screen", "") { model.toggleRecording() }
            tool("photo.on.rectangle.angled", "Convert images…", "") { convertingImages = true }
            tool("film", "Make a video smaller…", "") { pickVideos(gif: false) }
            tool("photo.stack", "Turn a video into a GIF…", "") { pickVideos(gif: true) }
        }
        .sheet(isPresented: $convertingImages) { ImageConversionSheet(model: model) }
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

    private var scratchpadView: some View {
        let current = model.currentTab
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.tabs) { tab in
                        Button { model.selectTab(tab.id) } label: {
                            Text(tab.title).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(tab.id == current.id ? Color.sonaryAccent.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { model.addTab() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("New note", bundle: .module))
                }
            }
            .scrollIndicators(.hidden)
            Group {
                if previewingMarkdown {
                    ScrollView {
                        Text(markdown: current.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                } else {
                    TextEditor(text: Binding(get: { current.text }, set: { model.setText($0, for: current.id) }))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                }
            }
            .frame(height: 260)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Toggle(isOn: $previewingMarkdown) {
                    Label { Text("Preview", bundle: .module) } icon: { Image(systemName: "doc.richtext") }
                }
                .toggleStyle(.button)
                Button { model.exportTab(current) } label: {
                    Label { Text("Save as Markdown", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                }
                Spacer()
                Button(role: .destructive) { model.removeTab(current.id) } label: {
                    Text("Delete note", bundle: .module)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func pickVideos(gif: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK else { return }
        if gif { model.makeGIFs(panel.urls) } else { model.compressVideos(panel.urls) }
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
        SettingsCard(Text("Capture", bundle: .module)) {
            SettingsToggleRow(symbol: "pencil.tip.crop.circle",
                              title: Text("Open the editor after a screenshot", bundle: .module),
                              caption: Text("Draw arrows and boxes, hide what should not be seen, put it on a background, then copy or save.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.annotateAfterCapture },
                                            set: { value in model.update { $0.annotateAfterCapture = value } }))
            SettingsToggleRow(symbol: "viewfinder.rectangular",
                              title: Text("Pick regions with Sonary's own selector", bundle: .module),
                              caption: Text("Dims the screen, shows a magnifier and the pixel size while you drag. Off uses the system selector.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.ownCaptureSelector },
                                            set: { value in model.update { $0.ownCaptureSelector = value } }))
        }
        SettingsCard(Text("Colour picker", bundle: .module)) {
            SettingsRow(symbol: "eyedropper", title: Text("Copy colours as", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.colorFormat },
                                          set: { value in model.update { $0.colorFormat = value } })) {
                    ForEach(ColorFormat.allCases, id: \.self) { format in
                        Text(verbatim: colorFormatExample(format)).tag(format)
                    }
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 220)
            }
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
        SettingsCard(Text("Scripts", bundle: .module)) {
            Text("Executable files in Sonary's scripts folder show up in the command bar. Only files you have marked executable are offered.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            Button { NSWorkspace.shared.open(scriptsFolder()) } label: {
                Text("Open the scripts folder", bundle: .module)
            }
            .buttonStyle(.borderless)
        }
        SettingsCard(Text("Extra rings", bundle: .module)) {
            Text("Each extra ring is a wedge in the first one that opens it, so the ring can hold more than eight actions without getting crowded.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.settings.radialProfiles) { profile in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(text: Binding(get: { profile.name },
                                                set: { model.renameRadialProfile(profile.id, to: $0) })) {
                            EmptyView()
                        }
                        .labelsHidden()
                        Spacer()
                        Button(role: .destructive) { model.removeRadialProfile(profile.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(QuickAction.allCases) { action in
                                let isOn = profile.actions.contains(action)
                                Button {
                                    model.setRadialProfileAction(profile.id, action: action, on: !isOn)
                                } label: {
                                    Image(systemName: action.symbol)
                                        .frame(width: 26, height: 22)
                                        .background(isOn ? Color.sonaryAccent.opacity(0.3) : Color.secondary.opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(quickActionTitle(action), bundle: .module))
                            }
                        }
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Button { model.addRadialProfile() } label: { Text("Add a ring", bundle: .module) }
                .buttonStyle(.borderless)
        }
        SettingsCard(Text("Snippets", bundle: .module)) {
            SettingsRow(symbol: "text.cursor", title: Text("Insert a snippet by", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.snippetDelivery },
                                          set: { value in model.update { $0.snippetDelivery = value } })) {
                    Text("Typing it", bundle: .module).tag(SnippetDelivery.type)
                    Text("Putting it on the clipboard", bundle: .module).tag(SnippetDelivery.clipboard)
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 220)
            }
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

/// Shows each format with the same example colour, so the choice explains itself.
func colorFormatExample(_ format: ColorFormat) -> String {
    formatColor(red: 1, green: 0.42, blue: 0.45, format: format)
}

extension Text {
    /// Renders Markdown, falling back to the plain text when it cannot be parsed.
    init(markdown: String) {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            self.init(attributed)
        } else {
            self.init(verbatim: markdown)
        }
    }
}

/// Picks the files, the format, a size limit and a watermark for a batch conversion.
struct ImageConversionSheet: View {
    let model: ToolsModel
    @Environment(\.dismiss) private var dismiss
    @State private var format: ImageFormat = .jpeg
    @State private var longestEdge = 0
    @State private var watermark = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Image conversion", bundle: .module).font(.headline)
            Picker(selection: $format) {
                ForEach(ImageFormat.allCases) { Text(verbatim: $0.rawValue.uppercased()).tag($0) }
            } label: { Text("Format", bundle: .module) }
            HStack {
                Text("Longest edge", bundle: .module)
                Spacer()
                TextField(value: $longestEdge, format: .number) { EmptyView() }
                    .labelsHidden().frame(width: 80)
                Text("px, 0 keeps the size", bundle: .module).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Watermark", bundle: .module)
                Spacer()
                TextField(text: $watermark) { EmptyView() }.labelsHidden().frame(width: 180)
            }
            Text("The converted copies land next to the originals.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                Button { pick() } label: { Text("Choose images…", bundle: .module) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 420)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        model.convertImages(panel.urls, to: format, longestEdge: max(0, longestEdge), watermark: watermark)
        dismiss()
    }
}
