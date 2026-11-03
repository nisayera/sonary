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
    public init() {}
}

/// Color picker, screenshots, text recognition, scratchpad, snippets and the command bar.
@MainActor
@Observable
public final class ToolsModel {
    public private(set) var settings: ToolsSettings
    public private(set) var lastResult: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hotKeys: [HotKey] = []
    @ObservationIgnored private var commandBar: CommandBarController?
    @ObservationIgnored private let radial = RadialMenuController()
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
            let hex = hexColor(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
            Task { @MainActor in
                self?.copy(hex)
                self?.lastResult = String(localized: "Copied \(hex)", bundle: .module)
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
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: image).perform([request])
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
