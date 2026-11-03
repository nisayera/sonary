import Foundation

public struct ClipboardSettings: Codable, Equatable, Sendable {
    public var historyLimit = 50
    public var cleanLinks = true
    /// ⌘⌥⇧V pastes the clipboard without formatting. Needs Accessibility to press ⌘V for you.
    public var plainTextPasteShortcut = false
    public var ignoredApps: [String] = []

    public init() {}
}

public struct ClipboardStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func loadSettings() -> ClipboardSettings {
        decode(ClipboardSettings.self, key: "clipboard.settings") ?? ClipboardSettings()
    }

    public func save(_ settings: ClipboardSettings) { encode(settings, key: "clipboard.settings") }

    public func loadHistory(limit: Int) -> ClipboardHistory {
        var history = decode(ClipboardHistory.self, key: "clipboard.history") ?? ClipboardHistory(limit: limit)
        history.limit = max(1, limit)
        return history
    }

    public func save(_ history: ClipboardHistory) { encode(history, key: "clipboard.history") }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
