import AppKit
import AVFoundation
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
    /// Extra rings, each a wedge in the first one.
    public var radialProfiles: [RadialProfile] = []
    /// Apps, files and shortcuts on wedges of the first ring, after its actions.
    public var radialLaunches: [RadialLaunch] = []
    /// The tools on the quick panel, in this order.
    public var quickPanelActions: [QuickAction] = [.screenshot, .textFromScreen, .colorPicker, .pinScreenshot,
                                                   .darkMode, .lockScreen, .cleaningMode, .commandBar]
    public var colorFormat: ColorFormat = .hex
    public var scratchpadTabs: [ScratchpadTab] = []
    /// Use Sonary's own region selector, with a magnifier, instead of the system one.
    public var ownCaptureSelector = false
    /// Whether a snippet is typed where the cursor is or put on the clipboard.
    public var snippetDelivery: SnippetDelivery = .type
    /// Open the editor on a fresh screenshot instead of only copying it.
    public var annotateAfterCapture = false
    /// Screen recordings carry what the Mac plays.
    public var recordSystemAudio = true
    /// Screen recordings carry the microphone too.
    public var recordMicrophone = false
    /// Typing a snippet's trigger anywhere replaces it with the snippet.
    public var snippetTriggers = false
    /// Holding ⌘ for a moment shows the front app's keyboard shortcuts.
    public var shortcutSheetOnHold = false
    /// How long ⌘ has to be held, in seconds.
    public var shortcutSheetDelay = 1.0
    /// Cleaning mode also swallows brightness, volume, media and Mission Control keys.
    public var cleaningBlocksSystemKeys = true
    /// Cleaning mode leaves the screen visible and shows a small badge instead of black.
    public var cleaningIndicatorOnly = false
    public var activeTab: UUID?
    public init() {}
}

/// Color picker, screenshots, text recognition, scratchpad, snippets and the command bar.
@MainActor
@Observable
public final class ToolsModel {
    public private(set) var settings: ToolsSettings
    public private(set) var lastResult: String?
    @ObservationIgnored private var resultTask: Task<Void, Never>?

    /// The command bar reports what it copied through this.
    var lastResultText: String? {
        get { lastResult }
        set { report(newValue) }
    }

    /// Shows a short note under the tools and takes it away again, so it cannot linger
    /// behind the next thing the panel shows.
    func report(_ text: String?) {
        lastResult = text
        resultTask?.cancel()
        guard text != nil else { return }
        resultTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.lastResult = nil
        }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var commandBar: CommandBarController?
    @ObservationIgnored private let radial = RadialMenuController()
    @ObservationIgnored private let cleaning = CleaningModeController()
    @ObservationIgnored private let pinned = PinnedImageController()
    @ObservationIgnored private let camera = CameraPreviewController()
    @ObservationIgnored private let recorder = ScreenRecorder()
    @ObservationIgnored private let selector = CaptureSelectorController()
    @ObservationIgnored private let editor = AnnotationEditorController()
    public private(set) var isRecording = false
    /// Commands other modules add to the command bar, for example the clipboard history.
    @ObservationIgnored public var externalCommands: @MainActor () -> [ExternalCommand] = { [] }
    @ObservationIgnored private var running = false
    @ObservationIgnored private let triggerTap = SnippetTriggerTap()
    @ObservationIgnored private let scratchpadWindow = ScratchpadWindowController()
    @ObservationIgnored private let quickPanel = QuickPanelController()
    @ObservationIgnored private let shortcutSheet = ShortcutSheetController()
    /// Set when the shortcut sheet could not start watching, which means Accessibility is missing.
    public private(set) var shortcutSheetNeedsAccessibility = false
    /// Set when the trigger watcher could not start, which means Accessibility is missing.
    public private(set) var snippetTriggersNeedAccessibility = false

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = StoredSettings.load(ToolsSettings.self, key: "tools.settings", from: defaults,
                                       fallback: ToolsSettings())
    }

    func start() {
        running = true
        applyShortcuts()
        applyTriggers()
        applyShortcutSheet()
    }

    func stop() {
        running = false
        applyShortcuts()
        applyTriggers()
        applyShortcutSheet()
        commandBar?.close()
        commandBar = nil
        radial.close()
        cleaning.stop()
        pinned.closeAll()
        camera.close()
        if isRecording { Task { await stopRecording() } }
        selector.close()
        editor.close()
        scratchpadWindow.close()
        quickPanel.close()
    }

    /// Starts or stops watching for a held ⌘, to match the settings.
    private func applyShortcutSheet() {
        shortcutSheet.delay = settings.shortcutSheetDelay
        guard running, settings.shortcutSheetOnHold else {
            shortcutSheet.stopWatching()
            shortcutSheetNeedsAccessibility = false
            return
        }
        shortcutSheetNeedsAccessibility = !shortcutSheet.startWatching()
    }

    /// Shows the front app's keyboard shortcuts, or closes the sheet when it is open.
    public func toggleShortcutSheet() {
        shortcutSheet.toggle()
    }

    /// The palette of favourite tools next to the pointer, or closes it when it is open.
    public func toggleQuickPanel() {
        quickPanel.toggle(actions: settings.quickPanelActions) { [weak self] action in self?.run(action) }
    }

    /// Opens the notes in a floating window of their own.
    public func showScratchpadWindow() {
        scratchpadWindow.show(model: self)
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
            report(String(localized: "Saved to \(url.lastPathComponent)", bundle: .module))
        } catch {
            report(String(localized: "Could not save the note.", bundle: .module))
        }
    }

    public func update(_ change: (inout ToolsSettings) -> Void) {
        let before = settings.shortcuts
        let triggersBefore = settings.snippetTriggers
        let sheetBefore = [settings.shortcutSheetOnHold ? 1 : 0, settings.shortcutSheetDelay]
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "tools.settings") }
        if before != settings.shortcuts { applyShortcuts() }
        if triggersBefore != settings.snippetTriggers { applyTriggers() }
        if sheetBefore != [settings.shortcutSheetOnHold ? 1 : 0, settings.shortcutSheetDelay] { applyShortcutSheet() }
    }

    /// Starts or stops watching for snippet triggers.
    private func applyTriggers() {
        guard running, settings.snippetTriggers else {
            triggerTap.stop()
            snippetTriggersNeedAccessibility = false
            return
        }
        triggerTap.snippets = { [weak self] in self?.settings.snippets ?? [] }
        triggerTap.expand = { [weak self] snippet in self?.expandTrigger(snippet) }
        snippetTriggersNeedAccessibility = !triggerTap.start()
    }

    /// Replaces a trigger that was just typed with its snippet: deletes the trigger, then
    /// types the snippet, once the trigger's last key has reached the app.
    private func expandTrigger(_ snippet: Snippet) {
        let typedLength = snippet.trigger?.count ?? 0
        let clipboard = NSPasteboard.general.string(forType: .string)
        let text = expandSnippet(snippet.text, now: Date(), clipboard: clipboard)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            TypeText.deleteBackward(typedLength)
            TypeText.type(text)
        }
    }

    private static let ctrlOpt = KeyModifier.control | KeyModifier.option

    /// What the tools offer the central shortcut page, and what each one runs.
    static var shortcutDefinitions: [ShortcutDefinition] { [
        ShortcutDefinition(id: "tools.commandBar", title: String(localized: "Command bar", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 49, modifiers: KeyModifier.option)),
        ShortcutDefinition(id: "tools.textFromScreen",
                           title: String(localized: "Copy text from screen", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 17, modifiers: ToolsModel.ctrlOpt)),
        ShortcutDefinition(id: "tools.colorPicker", title: String(localized: "Pick a color", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 35, modifiers: ToolsModel.ctrlOpt)),
        ShortcutDefinition(id: "tools.screenshot", title: String(localized: "Screenshot to clipboard", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 1, modifiers: ToolsModel.ctrlOpt)),
        ShortcutDefinition(id: "tools.radialMenu", title: String(localized: "Radial menu", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 15, modifiers: ToolsModel.ctrlOpt)),
        ShortcutDefinition(id: "tools.screenRecording", title: String(localized: "Record the screen", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: .none),
        ShortcutDefinition(id: "tools.scratchpad", title: String(localized: "Scratchpad in a window", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: .none),
        ShortcutDefinition(id: "tools.quickPanel", title: String(localized: "Quick panel", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: .none),
        ShortcutDefinition(id: "tools.shortcutSheet", title: String(localized: "Shortcut sheet", bundle: .module),
                           group: String(localized: "Tools", bundle: .module),
                           defaultCombo: .none),
    ] }

    private func applyShortcuts() {
        let shortcuts = ShortcutStore.shared
        shortcuts.describe(Self.shortcutDefinitions)
        shortcuts.unbindAll(prefix: "tools.")
        guard running, settings.shortcuts else { return }
        shortcuts.bind("tools.commandBar") { [weak self] in self?.showCommandBar() }
        shortcuts.bind("tools.textFromScreen") { [weak self] in self?.recognizeText() }
        shortcuts.bind("tools.colorPicker") { [weak self] in self?.pickColor() }
        shortcuts.bind("tools.screenshot") { [weak self] in self?.screenshotToClipboard() }
        shortcuts.bind("tools.radialMenu") { [weak self] in self?.showRadialMenu() }
        shortcuts.bind("tools.screenRecording") { [weak self] in self?.toggleRecording() }
        shortcuts.bind("tools.scratchpad") { [weak self] in self?.showScratchpadWindow() }
        shortcuts.bind("tools.quickPanel") { [weak self] in self?.toggleQuickPanel() }
        shortcuts.bind("tools.shortcutSheet") { [weak self] in self?.toggleShortcutSheet() }
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
            Task { @MainActor in self?.copyColor(red: red, green: green, blue: blue) }
        }
    }

    private func copyColor(red: Double, green: Double, blue: Double) {
        let value = formatColor(red: red, green: green, blue: blue, format: settings.colorFormat)
        copy(value)
        report(String(localized: "Copied \(value)", bundle: .module))
    }

    /// Takes a screenshot and keeps it floating on top until it is closed.
    public func pinScreenshot() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sonary-pin-\(UUID().uuidString).png")
        Task {
            guard let arguments = await captureArguments(["-x", file.path]),
                  await capture(arguments: arguments), let image = NSImage(contentsOf: file) else { return }
            try? FileManager.default.removeItem(at: file)
            pinned.pin(image)
        }
    }

    public func toggleCamera() { camera.toggle() }

    /// Captures a region, scrolls it and captures again, then hands the tall picture
    /// to the editor. Needs a region, so it always uses Sonary's own selector.
    public func scrollingScreenshot() {
        Task {
            guard let region = await withCheckedContinuation({ continuation in
                selector.show { continuation.resume(returning: $0) }
            }) else { return }
            report(String(localized: "Scrolling and capturing…", bundle: .module))
            let image = await captureScrolling(region: region) { [weak self] rect in
                await self?.captureImage(of: rect)
            }
            guard let image else {
                report(String(localized: "Nothing could be captured there.", bundle: .module))
                return
            }
            editor.open(image) { [weak self] message in self?.report(message) }
        }
    }

    /// One shot of a region, as a picture.
    private func captureImage(of rect: CGRect) async -> NSImage? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonary-scroll-\(UUID().uuidString).png")
        let value = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        guard await capture(arguments: ["-R", value, "-x", file.path]) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        return NSImage(contentsOf: file)
    }

    // MARK: Screen recording

    public func toggleRecording() {
        Task { isRecording ? await stopRecording() : await startRecording() }
    }

    /// Records the whole main display, or the region picked in the selector.
    private func startRecording(region: CGRect? = nil) async {
        guard !isRecording,
              let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent(recordingFileName(now: Date()))
        do {
            try await recorder.start(to: url, region: region.flatMap(Self.displayRegion),
                                     systemAudio: settings.recordSystemAudio, microphone: settings.recordMicrophone)
            isRecording = true
            report(String(localized: "Recording the screen.", bundle: .module))
        } catch {
            report(String(localized: "Allow Sonary to record the screen in System Settings > Privacy & Security.",
                          bundle: .module))
        }
    }

    private func stopRecording() async {
        let url = await recorder.stop()
        isRecording = false
        guard let url else {
            report(String(localized: "Nothing was recorded.", bundle: .module))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        report(String(localized: "Saved to \(url.lastPathComponent)", bundle: .module))
    }

    /// The display a region in screen coordinates is on, and the region within it with the
    /// origin at the top left, which is how ScreenCaptureKit measures.
    private static func displayRegion(_ rect: CGRect) -> RecordingRegion? {
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(middle) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let local = recordingSourceRect(rect, screenFrame: screen.frame)
        return RecordingRegion(displayID: number.uint32Value, rect: local, scale: screen.backingScaleFactor)
    }

    // MARK: Media tools

    /// Converts the images the user picked, scaling and watermarking them as asked.
    public func convertImages(_ urls: [URL], to format: ImageFormat, longestEdge: Int, watermark: String) {
        guard !urls.isEmpty else { return }
        Task {
            let written = await Task.detached { () -> Int in
                var done = 0
                for url in urls {
                    if (try? convertImage(at: url, to: format, longestEdge: longestEdge, watermark: watermark)) != nil {
                        done += 1
                    }
                }
                return done
            }.value
            if written == 0 {
                report(String(localized: "No image could be converted.", bundle: .module))
            } else {
                report(String(localized: "Converted \(written) images.", bundle: .module))
            }
        }
    }

    /// Turns the videos the user picked into animated GIFs.
    public func makeGIFs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            var written = 0
            for url in urls {
                if (try? await makeGIF(from: url)) != nil { written += 1 }
            }
            if written == 0 {
                report(String(localized: "No GIF could be made.", bundle: .module))
            } else {
                report(String(localized: "Made \(written) GIFs.", bundle: .module))
            }
        }
    }

    /// Keeps part of a video as a new file next to it.
    public func trimVideo(_ url: URL, start: Double, end: Double, removeAudio: Bool) {
        Task {
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard let range = trimRange(start: start, end: end, duration: duration) else {
                report(String(localized: "Nothing would be left of the video.", bundle: .module))
                return
            }
            do {
                let written = try await Tools.trimVideo(at: url, keeping: range, removeAudio: removeAudio)
                NSWorkspace.shared.activateFileViewerSelecting([written])
                report(String(localized: "Saved to \(written.lastPathComponent)", bundle: .module))
            } catch {
                report(String(localized: "The video could not be trimmed.", bundle: .module))
            }
        }
    }

    /// Re-encodes a video smaller, next to the original.
    public func compressVideos(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            var written = 0
            for url in urls {
                if (try? await compressVideo(at: url)) != nil { written += 1 }
            }
            if written == 0 {
                report(String(localized: "No video could be compressed.", bundle: .module))
            } else {
                report(String(localized: "Compressed \(written) videos.", bundle: .module))
            }
        }
    }

    public func screenshotToClipboard() { startCapture(.screenshot) }

    /// Lets you select an area of the screen and copies the text in it.
    public func recognizeText() { startCapture(.text) }

    /// Opens Sonary's selector in a mode, where 1 to 4 switch to another before the region
    /// is picked; with the system's selector the mode stays as it is.
    private func startCapture(_ mode: CaptureMode) {
        Task {
            guard settings.ownCaptureSelector else {
                await capture(mode, where: ["-i"])
                return
            }
            guard let choice = await withCheckedContinuation({ continuation in
                selector.show(mode: mode) { continuation.resume(returning: $0) }
            }) else { return }
            switch choice.mode {
            case .color:
                if let color = choice.color {
                    copyColor(red: color.red, green: color.green, blue: color.blue)
                } else {
                    pickColor()
                }
            case .recording:
                await startRecording(region: choice.rect)
            case .screenshot, .text:
                let rect = choice.rect
                await capture(choice.mode, where: ["-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"])
            }
        }
    }

    /// A screenshot or text from the region the arguments name.
    private func capture(_ mode: CaptureMode, where region: [String]) async {
        if mode == .text {
            await textFromScreen(region)
            return
        }
        guard settings.annotateAfterCapture else {
            guard await capture(arguments: region + ["-c"]) else { return }
            report(String(localized: "Screenshot copied to the clipboard.", bundle: .module))
            return
        }
        // The shot goes to a file first, so the editor has something to work on.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonary-shot-\(UUID().uuidString).png")
        guard await capture(arguments: region + ["-x", file.path]), let image = NSImage(contentsOf: file) else { return }
        try? FileManager.default.removeItem(at: file)
        editor.open(image) { [weak self] message in self?.report(message) }
    }

    private func textFromScreen(_ region: [String]) async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sonary-ocr-\(UUID().uuidString).png")
        guard await capture(arguments: region + ["-x", file.path]) else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        let text = await Task.detached { recognizedText(inImageAt: file) }.value
        if text.isEmpty {
            report(String(localized: "No text found.", bundle: .module))
        } else {
            copy(text)
            report(String(localized: "Text copied to the clipboard.", bundle: .module))
        }
    }

    /// Reads the text in image files the user picked and copies it, one file after another.
    public func textFromImageFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let text = await Task.detached { () -> String in
                urls.map { recognizedText(inImageAt: $0) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            }.value
            if text.isEmpty {
                report(String(localized: "No text found.", bundle: .module))
            } else {
                copy(text)
                report(String(localized: "Text copied to the clipboard.", bundle: .module))
            }
        }
    }

    /// Picks a region with whichever selector the user prefers, then runs the system
    /// screenshot tool on it. Nil when nothing was picked.
    private func region() async -> CGRect? {
        guard settings.ownCaptureSelector else { return nil }
        return await withCheckedContinuation { continuation in
            selector.show { continuation.resume(returning: $0) }
        }
    }

    /// The arguments that capture what the user picked: our own region, or the system
    /// selector when that is what they want.
    private func captureArguments(_ tail: [String]) async -> [String]? {
        guard settings.ownCaptureSelector else { return ["-i"] + tail }
        guard let rect = await region() else { return nil }
        let value = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        return ["-R", value] + tail
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
        let text = expandSnippet(snippet.text, now: Date(), clipboard: clipboard)
        guard settings.snippetDelivery == .type else {
            copy(text)
            report(String(localized: "Snippet copied. Press ⌘V to paste it.", bundle: .module))
            return
        }
        // The panel has the keyboard while it is open, so the text goes to whatever
        // had it before, once Sonary is out of the way.
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            TypeText.type(text)
        }
        report(String(localized: "Snippet typed.", bundle: .module))
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
        case .cleaningMode:
            cleaning.blocksSystemKeys = settings.cleaningBlocksSystemKeys
            cleaning.indicatorOnly = settings.cleaningIndicatorOnly
            cleaning.start()
        case .pinScreenshot: pinScreenshot()
        case .cameraPreview: camera.toggle()
        case .screenRecording: toggleRecording()
        case .scrollingShot: scrollingScreenshot()
        case .commandBar: showCommandBar()
        case .textFromScreen: recognizeText()
        case .colorPicker: pickColor()
        case .screenshot: screenshotToClipboard()
        }
    }

    public func showRadialMenu() {
        showRadialRing(radialRootItems(actions: settings.radialActions, launches: settings.radialLaunches,
                                       profiles: settings.radialProfiles))
    }

    private func showRadialRing(_ items: [RadialItem]) {
        radial.show(items: items, run: { [weak self] action in
            self?.run(action)
        }, launch: { [weak self] launch in
            self?.run(launch)
        }, open: { [weak self] profile in
            self?.showRadialRing(radialProfileItems(profile))
        }, back: { [weak self] in
            self?.showRadialMenu()
        })
    }

    /// Opens the app or file, or presses the shortcut in the app in front.
    public func run(_ launch: RadialLaunch) {
        switch launch {
        case .app(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        case .file(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .shortcut(let combo):
            Task { @MainActor in
                // Let the ring go first, so the keys reach the app behind it.
                try? await Task.sleep(for: .milliseconds(60))
                TypeText.press(combo)
            }
        }
    }

    public func setRadialProfileLaunches(_ id: UUID, _ launches: [RadialLaunch]) {
        update { settings in
            guard let index = settings.radialProfiles.firstIndex(where: { $0.id == id }) else { return }
            settings.radialProfiles[index].launches = launches
        }
    }

    public func addRadialProfile() {
        update { $0.radialProfiles.append(RadialProfile(name: String(localized: "New ring", bundle: .module))) }
    }

    public func removeRadialProfile(_ id: UUID) {
        update { $0.radialProfiles.removeAll { $0.id == id } }
    }

    public func renameRadialProfile(_ id: UUID, to name: String) {
        update { settings in
            guard let index = settings.radialProfiles.firstIndex(where: { $0.id == id }) else { return }
            settings.radialProfiles[index].name = name
        }
    }

    public func setRadialProfileAction(_ id: UUID, action: QuickAction, on: Bool) {
        update { settings in
            guard let index = settings.radialProfiles.firstIndex(where: { $0.id == id }) else { return }
            settings.radialProfiles[index].actions.removeAll { $0 == action }
            if on { settings.radialProfiles[index].actions.append(action) }
        }
    }

    // MARK: Command bar

    public func showCommandBar() {
        if commandBar == nil { commandBar = CommandBarController(model: self) }
        commandBar?.show()
    }
}

/// The text in a picture, or a QR code's or barcode's contents when it has one, since that
/// is what someone pointing at one is after. Empty when there is nothing to read.
func recognizedText(inImageAt url: URL) -> String {
    guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
    let handler = VNImageRequestHandler(cgImage: image)
    let barcodes = VNDetectBarcodesRequest()
    try? handler.perform([barcodes])
    let payloads = (barcodes.results ?? []).compactMap(\.payloadStringValue)
    if !payloads.isEmpty { return joinRecognizedLines(payloads) }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    // Without this only English is read, and umlauts and accents come out wrong.
    request.automaticallyDetectsLanguage = true
    try? handler.perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return joinRecognizedLines(lines)
}
