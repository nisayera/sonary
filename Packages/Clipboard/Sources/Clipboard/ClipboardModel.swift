import AppKit
import Observation

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
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        plainPasteKey?.unregister()
        plainPasteKey = nil
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        let types = board.types?.map(\.rawValue) ?? []
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard shouldRecord(types: types), !settings.ignoredApps.contains(frontmost ?? ""),
              let text = board.string(forType: .string) else { return }
        var recorded = text
        if settings.cleanLinks, let clean = cleanedURL(text) {
            board.clearContents()
            board.setString(clean, forType: .string)
            lastChangeCount = board.changeCount
            recorded = clean
        }
        history.add(recorded, at: Date(), sourceApp: frontmost)
        store.save(history)
    }

    // MARK: History

    public func copy(_ entry: ClipboardEntry) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(entry.text, forType: .string)
        lastChangeCount = board.changeCount
        history.add(entry.text, at: Date(), sourceApp: entry.sourceApp)
        store.save(history)
    }

    public func togglePin(_ entry: ClipboardEntry) {
        history.togglePin(entry.id)
        store.save(history)
    }

    public func remove(_ entry: ClipboardEntry) {
        history.remove(entry.id)
        store.save(history)
    }

    public func clearHistory() {
        history.clear()
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

    /// Replaces the clipboard with its plain text and presses ⌘V.
    func pastePlainText() {
        let board = NSPasteboard.general
        guard let text = board.string(forType: .string) else { return }
        board.clearContents()
        board.setString(text, forType: .string)
        lastChangeCount = board.changeCount
        guard AXIsProcessTrusted() else { return }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
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
        var url = folder.appendingPathComponent("\(base).txt")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).txt")
            n += 1
        }
        if FileManager.default.createFile(atPath: url.path, contents: Data()) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
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
