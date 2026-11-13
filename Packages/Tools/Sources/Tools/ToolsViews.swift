import AppKit
import SonaryCore
import SonaryUI
import SwiftUI
import UniformTypeIdentifiers

/// The tools panel as one list, as in Vorssaint: a row per group that opens in place, each on its
/// own, so nothing runs past the panel's edge.
struct ToolsPopoverView: View {
    let model: ToolsModel
    @AppStorage("panel.tools.open") private var open = "capture"
    @State private var convertingImages = false
    @State private var trimmingVideo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelDisclosure(symbol: "camera.viewfinder", title: Text("Capture", bundle: .module),
                            isExpanded: $open.opens("capture")) {
                PanelGroup {
                    tool("camera.viewfinder", "Screenshot to clipboard", shortcut: "tools.screenshot") { model.screenshotToClipboard() }
                    tool("text.viewfinder", "Copy text from screen", shortcut: "tools.textFromScreen") { model.recognizeText() }
                    tool("eyedropper", "Pick a color", shortcut: "tools.colorPicker") { model.pickColor() }
                    tool(model.isRecording ? "stop.circle" : "record.circle",
                         model.isRecording ? "Stop recording" : "Record the screen",
                         shortcut: "tools.screenRecording") { model.toggleRecording() }
                    tool("arrow.down.doc", "Scrolling screenshot") { model.scrollingScreenshot() }
                    tool("pin", "Pin a screenshot") { model.pinScreenshot() }
                }
            }
            PanelDisclosure(symbol: "bolt", title: Text("Quick access", bundle: .module),
                            isExpanded: $open.opens("launch")) {
                PanelGroup {
                    tool("magnifyingglass", "Command bar", shortcut: "tools.commandBar") { model.showCommandBar() }
                    tool("circle.grid.cross", "Radial menu", shortcut: "tools.radialMenu") { model.showRadialMenu() }
                    tool("square.grid.3x3", "Quick panel", shortcut: "tools.quickPanel") { model.toggleQuickPanel() }
                    tool("command", "Shortcut sheet", shortcut: "tools.shortcutSheet") { model.toggleShortcutSheet() }
                    tool("web.camera", "Camera mirror") { model.toggleCamera() }
                }
            }
            PanelDisclosure(symbol: "photo.on.rectangle.angled", title: Text("Media", bundle: .module),
                            isExpanded: $open.opens("media")) {
                PanelGroup {
                    tool("photo.on.rectangle.angled", "Convert images…") { convertingImages = true }
                    tool("film", "Make a video smaller…") { pickVideos(gif: false) }
                    tool("photo.stack", "Turn a video into a GIF…") { pickVideos(gif: true) }
                    tool("scissors", "Trim a video…") { trimmingVideo = true }
                    tool("doc.text.viewfinder", "Copy text from image files…") { pickImagesForText() }
                }
            }
            PanelDisclosure(symbol: "switch.2", title: Text("Toggles", bundle: .module),
                            isExpanded: $open.opens("toggles")) {
                togglesView
            }
            PanelDisclosure(symbol: "note.text", title: Text("Scratchpad", bundle: .module),
                            isExpanded: $open.opens("scratchpad")) {
                Text(verbatim: "\(model.tabs.count)")
            } content: {
                scratchpadView
            }
            PanelDisclosure(symbol: "text.quote", title: Text("Snippets", bundle: .module),
                            isExpanded: $open.opens("snippets")) {
                Text(verbatim: "\(model.settings.snippets.count)")
            } content: {
                snippetsView
            }
            if let result = model.lastResult {
                Text(result)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
        .sheet(isPresented: $convertingImages) { ImageConversionSheet(model: model) }
        .sheet(isPresented: $trimmingVideo) { VideoTrimSheet(model: model) }
    }

    private var togglesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelGroup {
                ForEach(quickToggleActions) { action in
                    Button { model.run(action) } label: {
                        PanelRow(symbol: action.symbol, title: Text(quickActionTitle(action), bundle: .module))
                    }
                    .buttonStyle(.plain)
                }
            }
            PanelNote(Text("Dark mode and the Trash ask once for permission to control the system.", bundle: .module))
        }
    }

    private var scratchpadView: some View {
        ScratchpadEditor(model: model, editorHeight: 180)
    }

    private func pickImagesForText() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        model.textFromImageFiles(panel.urls)
    }

    private func pickVideos(gif: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK else { return }
        if gif { model.makeGIFs(panel.urls) } else { model.compressVideos(panel.urls) }
    }

    /// A tool as a row, with the shortcut it has right now on the right: the user may have changed
    /// it on the Shortcuts page, and it shows only while the tools' shortcuts are on.
    private func tool(_ symbol: String, _ title: LocalizedStringKey, shortcut id: String? = nil,
                      action: @escaping () -> Void) -> some View {
        let combo = id.map { ShortcutStore.shared.combo(for: $0) } ?? KeyCombo.none
        let shortcut = model.settings.shortcuts ? shortcutDisplay(combo) : ""
        return Button(action: action) {
            PanelRow(symbol: symbol, title: Text(title, bundle: .module)) {
                if !shortcut.isEmpty {
                    Text(verbatim: shortcut)
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var snippetsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.settings.snippets.isEmpty {
                PanelGroup {
                    ForEach(model.settings.snippets) { snippet in
                        Button { model.insert(snippet) } label: {
                            PanelRow(symbol: "text.quote", title: Text(snippet.title),
                                     caption: Text(snippet.text.replacingOccurrences(of: "\n", with: " ")))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            PanelNote(Text("Edit snippets in Sonary's settings.", bundle: .module))
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
                              caption: Text("Dims the screen, shows a magnifier and the pixel size while you drag. 1 to 4 switch between screenshot, text, colour and recording, and a click takes the whole screen. Off uses the system selector.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.ownCaptureSelector },
                                            set: { value in model.update { $0.ownCaptureSelector = value } }))
        }
        SettingsCard(Text("Screen recording", bundle: .module)) {
            SettingsToggleRow(symbol: "speaker.wave.2", title: Text("Record the sound the Mac plays", bundle: .module),
                              isOn: Binding(get: { model.settings.recordSystemAudio },
                                            set: { value in model.update { $0.recordSystemAudio = value } }))
            SettingsToggleRow(symbol: "mic", title: Text("Record the microphone", bundle: .module),
                              caption: Text("Asks for the microphone the first time.", bundle: .module),
                              isOn: Binding(get: { model.settings.recordMicrophone },
                                            set: { value in model.update { $0.recordMicrophone = value } }))
        }
        SettingsCard(Text("Colour picker", bundle: .module)) {
            SettingsRow(symbol: "eyedropper", title: Text("Copy colours as", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.colorFormat },
                                          set: { value in model.update { $0.colorFormat = value } })) {
                    ForEach(ColorFormat.allCases, id: \.self) { format in
                        Text(verbatim: colorFormatExample(format)).tag(format)
                    }
                } label: { EmptyView() }
                    .settingsControl()
            }
        }
        SettingsCard(Text("Shortcut sheet", bundle: .module)) {
            SettingsToggleRow(symbol: "command", title: Text("Show an app's shortcuts while ⌘ is held", bundle: .module),
                              caption: Text("Hold ⌘ alone for a moment and every keyboard shortcut of the app in front appears, menu by menu. Let go to close it, or click a shortcut to run it. Needs Accessibility.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.shortcutSheetOnHold },
                                            set: { value in model.update { $0.shortcutSheetOnHold = value } }))
            if model.settings.shortcutSheetOnHold {
                SettingsRow(symbol: "hand.tap", title: Text("Opens with", bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.shortcutSheetTrigger },
                                              set: { value in
                                                  model.update {
                                                      $0.shortcutSheetTrigger = value
                                                      if value == .hold, $0.shortcutSheetDelay < 0.5 { $0.shortcutSheetDelay = 0.5 }
                                                  }
                                              })) {
                        Text("Holding ⌘", bundle: .module).tag(SheetTrigger.hold)
                        Text("Pressing ⌘ twice and holding", bundle: .module).tag(SheetTrigger.doubleHold)
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 230)
                }
                SettingsRow(symbol: "hourglass", title: Text("Hold ⌘ for", bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.shortcutSheetDelay },
                                              set: { value in model.update { $0.shortcutSheetDelay = value } })) {
                        if model.settings.shortcutSheetTrigger == .doubleHold {
                            Text("No wait", bundle: .module).tag(0.0)
                        }
                        Text(verbatim: "0.5 s").tag(0.5)
                        Text(verbatim: "1 s").tag(1.0)
                        Text(verbatim: "1.5 s").tag(1.5)
                        Text(verbatim: "2 s").tag(2.0)
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 100)
                }
            }
            SettingsRow(symbol: "rectangle.split.3x1", title: Text("Columns", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.shortcutSheetColumns },
                                          set: { value in model.update { $0.shortcutSheetColumns = value } })) {
                    Text("Automatic", bundle: .module).tag(0)
                    ForEach(2...5, id: \.self) { count in Text(verbatim: "\(count)").tag(count) }
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 130)
            }
            SettingsRow(symbol: "circle.lefthalf.filled", title: Text("Appearance", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.shortcutSheetAppearance },
                                          set: { value in model.update { $0.shortcutSheetAppearance = value } })) {
                    Text("Like the system", bundle: .module).tag(SheetAppearance.system)
                    Text("Light", bundle: .module).tag(SheetAppearance.light)
                    Text("Dark", bundle: .module).tag(SheetAppearance.dark)
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 150)
            }
            SettingsToggleRow(symbol: "apple.logo", title: Text("Show the system's shortcuts too", bundle: .module),
                              caption: Text("The sheet ends with the shortcuts macOS answers in every app, such as Spotlight and screenshots.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.shortcutSheetSystem },
                                            set: { value in model.update { $0.shortcutSheetSystem = value } }))
            SheetCustomShortcutsEditor(model: model)
            if model.settings.shortcutSheetMarks.values.contains(where: { !$0.isEmpty }) {
                SettingsRow(symbol: "star.slash", title: Text("Favourites and hidden shortcuts", bundle: .module)) {
                    Button { model.update { $0.shortcutSheetMarks = [:] } } label: { Text("Reset", bundle: .module) }
                }
            }
            if model.shortcutSheetNeedsAccessibility {
                SettingsWarning(Text("Sonary needs Accessibility for this. Allow it under System Settings → Privacy & Security → Accessibility, then switch this off and on again.",
                                     bundle: .module))
            }
            Text("It can also open on a shortcut of its own, from the Shortcuts page; then it stays until you close it.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard(Text("Quick panel", bundle: .module)) {
            Text("A small palette of your favourite tools next to the pointer. Give it a shortcut on the Shortcuts page.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickAction.allCases) { action in
                        let isOn = model.settings.quickPanelActions.contains(action)
                        Button {
                            model.update { settings in
                                settings.quickPanelActions.removeAll { $0 == action }
                                if !isOn { settings.quickPanelActions.append(action) }
                            }
                        } label: {
                            Image(systemName: action.symbol)
                                .frame(width: 28, height: 24)
                                .background(isOn ? Color.sonaryAccent.opacity(0.3) : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(Text(quickActionTitle(action), bundle: .module))
                        .accessibilityLabel(Text(quickActionTitle(action), bundle: .module))
                    }
                }
            }
            Button { model.toggleQuickPanel() } label: { Text("Try it", bundle: .module) }
                .buttonStyle(.borderless)
        }
        SettingsCard(Text("Cleaning mode", bundle: .module)) {
            SettingsToggleRow(symbol: "keyboard.badge.ellipsis", title: Text("Also block the system keys", bundle: .module),
                              caption: Text("Brightness, volume, media and Mission Control keys do nothing while you wipe. Needs Accessibility.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.cleaningBlocksSystemKeys },
                                            set: { value in model.update { $0.cleaningBlocksSystemKeys = value } }))
            SettingsToggleRow(symbol: "sparkles.rectangle.stack", title: Text("Show a small badge instead of a black screen", bundle: .module),
                              caption: Text("The screen stays visible and clicks are swallowed too, so the trackpad can be wiped. Escape ends it.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.cleaningIndicatorOnly },
                                            set: { value in model.update { $0.cleaningIndicatorOnly = value } }))
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
            Text("Apps, files and keyboard shortcuts get wedges after the actions.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            RadialLaunchEditor(launches: model.settings.radialLaunches) { launches in
                model.update { $0.radialLaunches = launches }
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
                        .help(Text("Remove this ring", bundle: .module))
                        .accessibilityLabel(Text("Remove this ring", bundle: .module))
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
                    RadialLaunchEditor(launches: profile.launches ?? []) { launches in
                        model.setRadialProfileLaunches(profile.id, launches)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Button { model.addRadialProfile() } label: { Text("Add a ring", bundle: .module) }
                .buttonStyle(.borderless)
        }
        SettingsCard(Text("Snippets", bundle: .module)) {
            SettingsToggleRow(symbol: "text.badge.plus", title: Text("Replace a trigger as you type it", bundle: .module),
                              caption: Text("Give a snippet a trigger such as ;sig, and typing it anywhere puts the snippet in its place. Needs Accessibility.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.snippetTriggers },
                                            set: { value in model.update { $0.snippetTriggers = value } }))
            if model.snippetTriggersNeedAccessibility {
                SettingsWarning(Text("Sonary needs Accessibility for this. Allow it under System Settings → Privacy & Security → Accessibility, then switch this off and on again.",
                                     bundle: .module))
            }
            SettingsRow(symbol: "text.cursor", title: Text("Insert a snippet by", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.snippetDelivery },
                                          set: { value in model.update { $0.snippetDelivery = value } })) {
                    Text("Typing it", bundle: .module).tag(SnippetDelivery.type)
                    Text("Putting it on the clipboard", bundle: .module).tag(SnippetDelivery.clipboard)
                } label: { EmptyView() }
                    .settingsControl()
            }
            Text("Placeholders: {date}, {time}, {clipboard}, and {date:yyyy-MM-dd} for a date in a format of your own.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.settings.snippets) { snippet in
                HStack(alignment: .top) {
                    VStack(spacing: 4) {
                        TextField(text: binding(snippet.id, \.title)) { Text("Title", bundle: .module) }
                        TextField(text: binding(snippet.id, \.text), axis: .vertical) { Text("Text", bundle: .module) }
                            .lineLimit(1...4)
                        if model.settings.snippetTriggers {
                            TextField(text: triggerBinding(snippet.id)) { Text("Trigger, such as ;sig", bundle: .module) }
                        }
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
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A snippet's trigger, with an empty field meaning none.
    private func triggerBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { model.settings.snippets.first { $0.id == id }?.trigger ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                model.update { settings in
                    if let index = settings.snippets.firstIndex(where: { $0.id == id }) {
                        settings.snippets[index].trigger = trimmed.isEmpty ? nil : trimmed
                    }
                }
            }
        )
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
                TextField(text: $watermark) { EmptyView() }.settingsControl()
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

/// The apps, files and shortcuts of a ring: each with its icon and a remove button, and ways
/// to add more.
struct RadialLaunchEditor: View {
    let launches: [RadialLaunch]
    let change: ([RadialLaunch]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(launches) { launch in
                HStack(spacing: 8) {
                    RadialLaunchIcon(launch: launch)
                    Text(verbatim: launch.title).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(role: .destructive) { change(launches.filter { $0 != launch }) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Remove", bundle: .module))
                }
                .font(.system(size: 12))
            }
            HStack(spacing: 8) {
                Button { choose(apps: true) } label: { Text("Add an app…", bundle: .module) }
                Button { choose(apps: false) } label: { Text("Add a file…", bundle: .module) }
                KeyPressRecorderButton(current: "", recordTitle: Text("Add a shortcut", bundle: .module),
                                       recordingTitle: Text("Press keys…", bundle: .module)) { keyCode, flags in
                    var modifiers = 0
                    if flags.contains(.command) { modifiers |= KeyModifier.command }
                    if flags.contains(.option) { modifiers |= KeyModifier.option }
                    if flags.contains(.control) { modifiers |= KeyModifier.control }
                    if flags.contains(.shift) { modifiers |= KeyModifier.shift }
                    add([.shortcut(KeyCombo(keyCode: Int(keyCode), modifiers: modifiers))])
                }
            }
            .controlSize(.small)
        }
    }

    private func add(_ new: [RadialLaunch]) {
        change(launches + new.filter { !launches.contains($0) })
    }

    private func choose(apps: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        if apps {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        } else {
            panel.canChooseDirectories = true
        }
        guard panel.runModal() == .OK else { return }
        add(panel.urls.map { apps ? .app(path: $0.path) : .file(path: $0.path) })
    }
}

private struct RadialLaunchIcon: View {
    let launch: RadialLaunch

    var body: some View {
        switch launch {
        case .app(let path), .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
        case .shortcut:
            Image(systemName: "command").frame(width: 18, height: 18).foregroundStyle(.secondary)
        }
    }
}

/// The notes with their tabs, Markdown preview and export: in the menu panel, and in a
/// window of their own that stays in front.
struct ScratchpadEditor: View {
    let model: ToolsModel
    /// A fixed height in the panel; nil fills the window.
    let editorHeight: CGFloat?
    @State private var previewingMarkdown = false

    var body: some View {
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
            .frame(minHeight: editorHeight ?? 160, maxHeight: editorHeight ?? .infinity)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Toggle(isOn: $previewingMarkdown) {
                    Label { Text("Preview", bundle: .module) } icon: { Image(systemName: "doc.richtext") }
                }
                .toggleStyle(.button)
                Button { model.exportTab(current) } label: {
                    Label { Text("Save as Markdown", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                }
                if editorHeight != nil {
                    Button { model.showScratchpadWindow() } label: { Image(systemName: "macwindow.badge.plus") }
                        .help(Text("Open in a window", bundle: .module))
                        .accessibilityLabel(Text("Open in a window", bundle: .module))
                }
                Spacer()
                Button(role: .destructive) { model.removeTab(current.id) } label: {
                    Text("Delete note", bundle: .module)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Picks a video, then the part of it to keep, in seconds.
struct VideoTrimSheet: View {
    let model: ToolsModel
    @Environment(\.dismiss) private var dismiss
    @State private var video: URL?
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var removeAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Trim a video", bundle: .module).font(.headline)
            HStack {
                Text(verbatim: video?.lastPathComponent ?? "—").lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { choose() } label: { Text("Choose a video…", bundle: .module) }
            }
            HStack {
                Text("Keep from", bundle: .module)
                TextField(value: $start, format: .number.precision(.fractionLength(0...2))) { EmptyView() }
                    .labelsHidden().frame(width: 70)
                Text("to", bundle: .module)
                TextField(value: $end, format: .number.precision(.fractionLength(0...2))) { EmptyView() }
                    .labelsHidden().frame(width: 70)
                Text("seconds", bundle: .module)
            }
            Text("0 as the end keeps everything to the end. The trimmed copy lands next to the original.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: $removeAudio) { Text("Remove the sound", bundle: .module) }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                Button {
                    if let video { model.trimVideo(video, start: start, end: end, removeAudio: removeAudio) }
                    dismiss()
                } label: { Text("Trim", bundle: .module) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(video == nil)
            }
        }
        .padding(Spacing.l)
        .frame(width: 420)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        guard panel.runModal() == .OK else { return }
        video = panel.url
    }
}

/// The shortcuts written down by hand, under "My shortcuts" in the sheet: a name, the
/// keys as they should be printed, and the app they belong to.
struct SheetCustomShortcutsEditor: View {
    let model: ToolsModel

    private var apps: [(id: String, name: String)] {
        var seen = Set<String>()
        var result: [(id: String, name: String)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { continue }
            result.append((id, app.localizedName ?? id))
        }
        for entry in model.settings.shortcutSheetCustom {
            if let id = entry.bundleID, seen.insert(id).inserted { result.append((id, id)) }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("My shortcuts", bundle: .module).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    model.update { $0.shortcutSheetCustom.append(CustomSheetShortcut(title: "", keys: "")) }
                } label: {
                    Label { Text("Add", bundle: .module) } icon: { Image(systemName: "plus") }
                }
            }
            Text("For shortcuts the menus do not show. Write the keys the way they should be printed, for example ⌃⌥T.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            let apps = apps
            ForEach(model.settings.shortcutSheetCustom) { entry in
                HStack(spacing: 6) {
                    TextField(text: binding(entry.id, \.title)) { Text("Name", bundle: .module) }
                        .textFieldStyle(.roundedBorder)
                    TextField(text: binding(entry.id, \.keys)) { Text("Keys", bundle: .module) }
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                    Picker(selection: Binding(get: { entry.bundleID ?? "" },
                                              set: { value in
                                                  model.update { settings in
                                                      guard let index = settings.shortcutSheetCustom.firstIndex(where: { $0.id == entry.id }) else { return }
                                                      settings.shortcutSheetCustom[index].bundleID = value.isEmpty ? nil : value
                                                  }
                                              })) {
                        Text("All apps", bundle: .module).tag("")
                        ForEach(apps, id: \.id) { app in Text(verbatim: app.name).tag(app.id) }
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 140)
                    Button {
                        model.update { $0.shortcutSheetCustom.removeAll { $0.id == entry.id } }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Remove", bundle: .module))
                }
            }
        }
    }

    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<CustomSheetShortcut, String>) -> Binding<String> {
        Binding(get: { model.settings.shortcutSheetCustom.first { $0.id == id }?[keyPath: keyPath] ?? "" },
                set: { value in
                    model.update { settings in
                        guard let index = settings.shortcutSheetCustom.firstIndex(where: { $0.id == id }) else { return }
                        settings.shortcutSheetCustom[index][keyPath: keyPath] = value
                    }
                })
    }
}
