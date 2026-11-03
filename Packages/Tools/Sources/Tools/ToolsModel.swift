import AppKit
import Observation
import SonaryCore
import Vision

public struct ToolsSettings: Codable, Equatable, Sendable {
    public var shortcuts = true
    public var scratchpad = ""
    public var snippets: [Snippet] = [
        Snippet(title: "Date", text: "{date}"),
    ]
    public var radialActions: [QuickAction] = QuickAction.allCases
    public var colorFormat: ColorFormat = .hex
    public var scratchpadTabs: [ScratchpadTab] = []
    public var activeTab: UUID?
    public init() {}
}

/// Color picker, screenshots, text recognition, scratchpad, snippets and the command bar.
@MainActor
@Observable
public final class ToolsModel {
    public private(set) var settings: ToolsSettings
    public private(set) var lastResult: String?

    /// The command bar reports what it copied through this.
    var lastResultText: String? {
        get { lastResult }
        set { lastResult = newValue }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hotKeys: [HotKey] = []
    @ObservationIgnored private var commandBar: CommandBarController?
    @ObservationIgnored private let radial = RadialMenuController()
    @ObservationIgnored private let cleaning = CleaningModeController()
    @ObservationIgnored private var running = false

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "tools.settings"),
           let settings = try? JSONDecoder().decode(ToolsSettings.self, from: data) {
            self.settings = settings
        } else {
            settings = ToolsSettings()
        }
    }

    func start() {
        running = true
        applyShortcuts()
    }

    func stop() {
        running = false
        applyShortcuts()
        commandBar?.close()
        commandBar = nil
        radial.close()
        cleaning.stop()
    }

    /// The notes, with the old single scratchpad carried over the first time.
    public var tabs: [ScratchpadTab] {
        if settings.scratchpadTabs.isEmpty {
            return [ScratchpadTab(title: String(localized: "Note", bundle: .module), text: settings.scratchpad)]
        }
        return settings.scratchpadTabs
    }

    public var currentTab: ScratchpadTab {
        tabs.first { $0.id == settings.activeTab } ?? tabs[0]
    }

    public func selectTab(_ id: UUID) {
        update { $0.activeTab = id }
    }

    public func addTab() {
        let tab = ScratchpadTab(title: String(localized: "Note", bundle: .module))
        update { settings in
            if settings.scratchpadTabs.isEmpty { settings.scratchpadTabs = self.tabs }
            settings.scratchpadTabs.append(tab)
            settings.activeTab = tab.id
        }
    }

    public func removeTab(_ id: UUID) {
        update { settings in
            if settings.scratchpadTabs.isEmpty { settings.scratchpadTabs = self.tabs }
            settings.scratchpadTabs.removeAll { $0.id == id }
            if settings.scratchpadTabs.isEmpty {
                settings.scratchpadTabs = [ScratchpadTab(title: String(localized: "Note", bundle: .module))]
            }
            if settings.activeTab == id { settings.activeTab = settings.scratchpadTabs.first?.id }
        }
    }

    public func setText(_ text: String, for id: UUID) {
        update { settings in
            if settings.scratchpadTabs.isEmpty { settings.scratchpadTabs = self.tabs }
            guard let index = settings.scratchpadTabs.firstIndex(where: { $0.id == id }) else { return }
            settings.scratchpadTabs[index].text = text
            settings.scratchpadTabs[index].title = suggestedTitle(
                for: text, fallback: String(localized: "Note", bundle: .module))
        }
    }

    /// Writes the note to the Downloads folder as Markdown and shows it in the Finder.
    public func exportTab(_ tab: ScratchpadTab) {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent(exportFileName(for: tab.title,
                                                               fallback: String(localized: "Note", bundle: .module)))
        do {
            try tab.text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            lastResult = String(localized: "Saved to \(url.lastPathComponent)", bundle: .module)
        } catch {
            lastResult = String(localized: "Could not save the note.", bundle: .module)
        }
    }

    public func update(_ change: (inout ToolsSettings) -> Void) {
        let before = settings.shortcuts
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "tools.settings") }
        if before != settings.shortcuts { applyShortcuts() }
    }

    private func applyShortcuts() {
        hotKeys.forEach { $0.unregister() }
        hotKeys = []
        guard running, settings.shortcuts else { return }
        let ctrlOpt = 4096 | 2048
        let bindings: [(Int, Int, () -> Void)] = [
            (49, 2048, { [weak self] in self?.showCommandBar() }),          // ⌥Space
            (17, ctrlOpt, { [weak self] in self?.recognizeText() }),          // ⌃⌥T
            (35, ctrlOpt, { [weak self] in self?.pickColor() }),              // ⌃⌥P
            (1, ctrlOpt, { [weak self] in self?.screenshotToClipboard() }),   // ⌃⌥S
            (15, ctrlOpt, { [weak self] in self?.showRadialMenu() }),         // ⌃⌥R
        ]
        for (key, modifiers, action) in bindings {
            if let hotKey = HotKey(keyCode: key, modifiers: modifiers, action: action) { hotKeys.append(hotKey) }
        }
    }

    // MARK: Tools

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            // NSColor is not Sendable, so only the numbers cross into the main actor.
            let red = Double(color.redComponent), green = Double(color.greenComponent), blue = Double(color.blueComponent)
            Task { @MainActor in
                guard let self else { return }
                let value = formatColor(red: red, green: green, blue: blue, format: self.settings.colorFormat)
                self.copy(value)
                self.lastResult = String(localized: "Copied \(value)", bundle: .module)
            }
        }
    }

    public func screenshotToClipboard() {
        Task {
            _ = await capture(arguments: ["-i", "-c"])
            lastResult = String(localized: "Screenshot copied to the clipboard.", bundle: .module)
        }
    }

    /// Lets you select an area of the screen and copies the text in it.
    public func recognizeText() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sonary-ocr-\(UUID().uuidString).png")
        Task {
            guard await capture(arguments: ["-i", "-x", file.path]) else { return }
            defer { try? FileManager.default.removeItem(at: file) }
            let text = await Task.detached { () -> String in
                guard let image = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
                let handler = VNImageRequestHandler(cgImage: image)
                // A QR code or barcode in the selection is what the user is after, so it wins over loose text.
                let barcodes = VNDetectBarcodesRequest()
                try? handler.perform([barcodes])
                let payloads = (barcodes.results ?? []).compactMap(\.payloadStringValue)
                if !payloads.isEmpty { return joinRecognizedLines(payloads) }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                return joinRecognizedLines(lines)
            }.value
            if text.isEmpty {
                lastResult = String(localized: "No text found.", bundle: .module)
            } else {
                copy(text)
                lastResult = String(localized: "Text copied to the clipboard.", bundle: .module)
            }
        }
    }

    /// Runs the system screenshot tool; false when it failed or was cancelled.
    private func capture(arguments: [String]) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            do { try process.run() } catch { return false }
            process.waitUntilExit()
            if let path = arguments.last, path.hasPrefix("/") { return FileManager.default.fileExists(atPath: path) }
            return process.terminationStatus == 0
        }.value
    }

    // MARK: Snippets

    public func insert(_ snippet: Snippet) {
        let clipboard = NSPasteboard.general.string(forType: .string)
        copy(expandSnippet(snippet.text, now: Date(), clipboard: clipboard))
        lastResult = String(localized: "Snippet copied. Press ⌘V to paste it.", bundle: .module)
    }

    public func addSnippet() {
        update { $0.snippets.append(Snippet(title: String(localized: "New snippet", bundle: .module), text: "")) }
    }

    public func removeSnippet(_ id: UUID) { update { $0.snippets.removeAll { $0.id == id } } }

    // MARK: Quick actions and the radial menu

    public func run(_ action: QuickAction) {
        switch action {
        case .darkMode: SystemActions.toggleDarkMode()
        case .desktopIcons: SystemActions.toggleDesktopIcons()
        case .emptyTrash: SystemActions.emptyTrash()
        case .ejectDisks: SystemActions.ejectDisks()
        case .lockScreen: SystemActions.lockScreen()
        case .cleaningMode: cleaning.start()
        case .commandBar: showCommandBar()
        case .textFromScreen: recognizeText()
        case .colorPicker: pickColor()
        case .screenshot: screenshotToClipboard()
        }
    }

    public func showRadialMenu() {
        let actions = settings.radialActions.isEmpty ? QuickAction.allCases : settings.radialActions
        radial.show(actions: Array(actions.prefix(8))) { [weak self] action in self?.run(action) }
    }

    // MARK: Command bar

    public func showCommandBar() {
        if commandBar == nil { commandBar = CommandBarController(model: self) }
        commandBar?.show()
    }
}
