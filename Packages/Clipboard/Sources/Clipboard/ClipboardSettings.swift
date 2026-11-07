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

public struct ClipboardStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func loadSettings() -> ClipboardSettings {
        StoredSettings.load(ClipboardSettings.self, key: "clipboard.settings", from: defaults,
                            fallback: ClipboardSettings())
    }

    public func save(_ settings: ClipboardSettings) { encode(settings, key: "clipboard.settings") }

    public func loadHistory(limit: Int) -> ClipboardHistory {
        var history = StoredSettings.load(ClipboardHistory.self, key: "clipboard.history", from: defaults,
                                          fallback: ClipboardHistory(limit: limit))
        history.limit = max(1, limit)
        return history
    }

    public func save(_ history: ClipboardHistory) { encode(history, key: "clipboard.history") }

    private func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
