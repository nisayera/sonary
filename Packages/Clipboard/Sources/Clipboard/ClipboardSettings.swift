import Foundation
import SonaryCore

public struct ClipboardSettings: Codable, Equatable, Sendable {
    public var historyLimit = 50
    public var cleanLinks = true
    /// ⌘⌥⇧V pastes the clipboard without formatting. Needs Accessibility to press ⌘V for you.
    public var plainTextPasteShortcut = false
    public var ignoredApps: [String] = []
    public var captureImages = true
    public var captureFiles = true
    /// Minutes after which unpinned entries are dropped; 0 keeps them.
    public var autoClearMinutes = 0
    public var clearOnSleep = false
    public var clearOnLock = false
    /// The quick panel pastes the entry you pick; off, it only puts it on the clipboard.
    public var quickPanelPastes = true
    /// A small shelf appears next to the pointer while files are dragged.
    public var floatingShelf = false
    /// ⌘X and ⌘V move files in Finder.
    public var finderCutAndPaste = false
    /// F2 renames the selected item in Finder.
    public var finderRenameWithF2 = false

    public init() {}
}

/// Keeps the clipboard settings in UserDefaults and the history in its own file.
///
/// The history used to live in UserDefaults as well: up to 500 copies in plain text inside the
/// preferences plist, which every process that reads preferences could see and which was
/// rewritten completely on the main thread with every copy. It now lives in
/// `~/Library/Application Support/Sonary/Clipboard/history.json`, in a folder only you can open
/// (0700, the file 0600), kept out of Time Machine, and written in the background. A history
/// that is still in UserDefaults is moved to the file on first launch.
public struct ClipboardStore {
    private static let historyKey = "clipboard.history"
    /// One queue, so writes land in the order they were made.
    private static let writer = DispatchQueue(label: "app.sonary.clipboard.history", qos: .utility)

    private let defaults: UserDefaults
    /// Nil keeps the history in `defaults`, which only tests do.
    private let historyFile: URL?

    public init(defaults: UserDefaults, historyFile: URL? = nil) {
        self.defaults = defaults
        self.historyFile = historyFile
    }

    /// The history file for the app's own preferences. Other `UserDefaults` (tests, previews)
    /// get none, so they never read or overwrite the history of the Sonary you are using.
    public static func defaultHistoryFile(for defaults: UserDefaults) -> URL? {
        guard defaults === UserDefaults.standard,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appendingPathComponent("Sonary/Clipboard/history.json", isDirectory: false)
    }

    public func loadSettings() -> ClipboardSettings {
        StoredSettings.load(ClipboardSettings.self, key: "clipboard.settings", from: defaults,
                            fallback: ClipboardSettings())
    }

    public func save(_ settings: ClipboardSettings) {
        StoredSettings.save(settings, key: "clipboard.settings", to: defaults)
    }

    public func loadHistory(limit: Int) -> ClipboardHistory {
        let fallback = ClipboardHistory(limit: limit)
        var history: ClipboardHistory
        if let historyFile {
            if let data = try? Data(contentsOf: historyFile) {
                history = StoredSettings.decode(ClipboardHistory.self, from: data, fallback: fallback)
            } else if let legacy = defaults.data(forKey: Self.historyKey) {
                history = StoredSettings.decode(ClipboardHistory.self, from: legacy, fallback: fallback)
                // The key goes only once the file is written, so a failed move loses nothing.
                if let data = try? JSONEncoder().encode(history), (try? Self.write(data, to: historyFile)) != nil {
                    defaults.removeObject(forKey: Self.historyKey)
                }
            } else {
                history = fallback
            }
        } else {
            history = StoredSettings.load(ClipboardHistory.self, key: Self.historyKey, from: defaults,
                                          fallback: fallback)
        }
        history.limit = max(1, limit)
        return history
    }

    public func save(_ history: ClipboardHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        guard let historyFile else {
            defaults.set(data, forKey: Self.historyKey)
            return
        }
        Self.writer.async { try? Self.write(data, to: historyFile) }
    }

    /// Returns once every save made so far is on disk.
    public func flush() {
        Self.writer.sync {}
    }

    static func write(_ data: Data, to file: URL) throws {
        let manager = FileManager.default
        let folder = file.deletingLastPathComponent()
        if !manager.fileExists(atPath: folder.path) {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        }
        try data.write(to: file, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
