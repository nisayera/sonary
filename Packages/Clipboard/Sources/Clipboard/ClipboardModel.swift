import AppKit
import Observation
import SonaryCore

/// Records text copies (polling the pasteboard), cleans links, keeps a file shelf and offers Finder helpers.
@MainActor
@Observable
public final class ClipboardModel {
    public private(set) var history: ClipboardHistory
    public private(set) var settings: ClipboardSettings
    public private(set) var shelf: [URL] = []
    public private(set) var lastMessage: String?

    @ObservationIgnored private let store: ClipboardStore
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var plainPasteKey: HotKey?
    @ObservationIgnored private var autoClearTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var lockObserver: (any NSObjectProtocol)?

    /// Where copied images are kept, next to the rest of Sonary's data.
    private var imageFolder: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("app.sonary.Sonary/clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public init(defaults: UserDefaults) {
        store = ClipboardStore(defaults: defaults)
        let settings = store.loadSettings()
        self.settings = settings
        history = store.loadHistory(limit: settings.historyLimit)
    }

    func start() {
        guard pollTask == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        applyShortcut()
        startAutoClear()
        observeSleepAndLock()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        plainPasteKey?.unregister()
        plainPasteKey = nil
        autoClearTask?.cancel()
        autoClearTask = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
        sleepObserver = nil
        lockObserver = nil
    }

    private func startAutoClear() {
        guard autoClearTask == nil else { return }
        autoClearTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.runAutoClear()
            }
        }
    }

    private func runAutoClear() {
        guard settings.autoClearMinutes > 0 else { return }
        let dropped = history.autoClear(now: Date(), olderThanMinutes: settings.autoClearMinutes)
        guard !dropped.isEmpty else { return }
        removeImageFiles(of: dropped)
        store.save(history)
    }

    private func observeSleepAndLock() {
        if sleepObserver == nil {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { if self?.settings.clearOnSleep == true { self?.clearHistory() } }
            }
        }
        if lockObserver == nil {
            lockObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { if self?.settings.clearOnLock == true { self?.clearHistory() } }
            }
        }
    }

    /// Deletes the image files of entries that are gone.
    private func removeImageFiles(of entries: [ClipboardEntry]) {
        guard let folder = imageFolder else { return }
        for entry in entries {
            guard case let .image(fileName) = entry.content else { continue }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
        }
    }

    public func imageURL(for entry: ClipboardEntry) -> URL? {
        guard case let .image(fileName) = entry.content, let folder = imageFolder else { return nil }
        return folder.appendingPathComponent(fileName)
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        let types = board.types?.map(\.rawValue) ?? []
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard shouldRecord(types: types), !settings.ignoredApps.contains(frontmost ?? "") else { return }

        if let text = board.string(forType: .string) {
            var recorded = text
            if settings.cleanLinks, let clean = cleanedURL(text) {
                board.clearContents()
                board.setString(clean, forType: .string)
                lastChangeCount = board.changeCount
                recorded = clean
            }
            history.add(recorded, at: Date(), sourceApp: frontmost)
            store.save(history)
            return
        }
        if settings.captureFiles,
           let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            history.add(.files(urls.map(\.path)), at: Date(), sourceApp: frontmost)
            store.save(history)
            return
        }
        if settings.captureImages, let fileName = saveImageFromPasteboard(board) {
            history.add(.image(fileName: fileName), at: Date(), sourceApp: frontmost)
            store.save(history)
        }
    }

    // MARK: History

    /// Writes a copied image to the cache folder as PNG and returns its file name.
    private func saveImageFromPasteboard(_ board: NSPasteboard) -> String? {
        guard let folder = imageFolder,
              let image = NSImage(pasteboard: board),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let fileName = "\(UUID().uuidString).png"
        do {
            try png.write(to: folder.appendingPathComponent(fileName))
        } catch {
            return nil
        }
        return fileName
    }

    public func copy(_ entry: ClipboardEntry) {
        let board = NSPasteboard.general
        board.clearContents()
        switch entry.content {
        case let .text(value):
            board.setString(value, forType: .string)
        case .image:
            guard let url = imageURL(for: entry), let image = NSImage(contentsOf: url) else { return }
            board.writeObjects([image])
        case let .files(paths):
            board.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        }
        lastChangeCount = board.changeCount
        history.add(entry.content, at: Date(), sourceApp: entry.sourceApp)
        store.save(history)
    }

    public func togglePin(_ entry: ClipboardEntry) {
        history.togglePin(entry.id)
        store.save(history)
    }

    public func remove(_ entry: ClipboardEntry) {
        history.remove(entry.id)
        removeImageFiles(of: [entry])
        store.save(history)
    }

    public func clearHistory() {
        let gone = history.entries.filter { !$0.isPinned }
        history.clear()
        removeImageFiles(of: gone)
        store.save(history)
    }

    // MARK: Settings

    public func update(_ change: (inout ClipboardSettings) -> Void) {
        let before = settings
        change(&settings)
        settings.historyLimit = min(max(settings.historyLimit, 10), 500)
        store.save(settings)
        if settings.historyLimit != before.historyLimit {
            history.setLimit(settings.historyLimit)
            store.save(history)
        }
        if settings.plainTextPasteShortcut != before.plainTextPasteShortcut {
            applyShortcut()
            if settings.plainTextPasteShortcut, !AXIsProcessTrusted() {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }
    }

    private func applyShortcut() {
        plainPasteKey?.unregister()
        plainPasteKey = nil
        guard settings.plainTextPasteShortcut, pollTask != nil else { return }
        // ⌘⌥⇧V (key code 9 is V).
        plainPasteKey = HotKey(keyCode: 9, modifiers: 256 | 2048 | 512) { [weak self] in self?.pastePlainText() }
    }

    /// Pastes the clipboard without its formatting and puts the original contents back afterwards.
    func pastePlainText() {
        let board = NSPasteboard.general
        guard let text = board.string(forType: .string) else { return }
        let saved = snapshot(board)
        board.clearContents()
        board.setString(text, forType: .string)
        lastChangeCount = board.changeCount
        guard AXIsProcessTrusted() else { return }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        Task { [weak self] in
            // Give the app a moment to read the pasteboard before it changes back.
            try? await Task.sleep(for: .milliseconds(350))
            self?.restore(saved, to: board)
        }
    }

    private func snapshot(_ board: NSPasteboard) -> [[String: Data]] {
        (board.pasteboardItems ?? []).map { item in
            var stored: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { stored[type.rawValue] = data }
            }
            return stored
        }
    }

    private func restore(_ snapshot: [[String: Data]], to board: NSPasteboard) {
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        board.clearContents()
        board.writeObjects(items)
        lastChangeCount = board.changeCount
    }

    // MARK: Shelf

    public func addToShelf(_ urls: [URL]) {
        for url in urls where !shelf.contains(url) { shelf.append(url) }
    }

    public func removeFromShelf(_ url: URL) { shelf.removeAll { $0 == url } }
    public func clearShelf() { shelf.removeAll() }

    // MARK: Finder

    public func copyFinderSelectionPaths() {
        let script = """
        tell application "Finder"
            set out to ""
            repeat with anItem in (selection as alias list)
                set out to out & POSIX path of anItem & linefeed
            end repeat
            return out
        end tell
        """
        guard let paths = runFinderScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines), !paths.isEmpty else {
            lastMessage = String(localized: "Select files in Finder first.", bundle: .module)
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(paths, forType: .string)
        lastMessage = String(localized: "Path copied.", bundle: .module)
    }

    public func openTerminalInFinderFolder() {
        guard let folder = currentFinderFolder(),
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    public func newTextFileInFinderFolder() {
        guard let folder = currentFinderFolder() else { return }
        let base = String(localized: "Untitled", bundle: .module)
        let name = uniqueFileName(base: base, extension: "txt") {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let url = folder.appendingPathComponent(name)
        if FileManager.default.createFile(atPath: url.path, contents: Data()) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Writes the image on the clipboard into the front Finder window as a PNG.
    public func saveClipboardImageToFinderFolder() {
        guard let folder = currentFinderFolder() else { return }
        guard let image = NSImage(pasteboard: .general),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            lastMessage = String(localized: "There is no image on the clipboard.", bundle: .module)
            return
        }
        let name = uniqueFileName(base: clipboardImageName(now: Date()), extension: "png") {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let url = folder.appendingPathComponent(name)
        do {
            try png.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            lastMessage = String(localized: "Saved \(name).", bundle: .module)
        } catch {
            lastMessage = String(localized: "Could not save the image there.", bundle: .module)
        }
    }

    private func currentFinderFolder() -> URL? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as alias)
            else
                return POSIX path of (desktop as alias)
            end if
        end tell
        """
        guard let path = runFinderScript(script), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func runFinderScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil {
            lastMessage = String(localized: "Allow Sonary to control Finder in System Settings > Privacy & Security > Automation.",
                                 bundle: .module)
            return nil
        }
        return result?.stringValue
    }
}
