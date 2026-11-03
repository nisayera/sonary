import Foundation

public enum NotchWidget: String, Codable, CaseIterable, Sendable {
    case music, calendar, timer, downloads, batteries

    public var symbol: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        case .timer: "timer"
        case .downloads: "arrow.down.circle"
        case .batteries: "battery.75percent"
        }
    }
}

public struct NotchSettings: Codable, Equatable, Sendable {
    /// Calendar starts off because it asks for access.
    public var widgets: [NotchWidget] = [.music, .timer, .downloads, .batteries]
    public var showOnScreensWithoutNotch = true

    public init() {}

    public func isOn(_ widget: NotchWidget) -> Bool { widgets.contains(widget) }

    public mutating func set(_ widget: NotchWidget, on: Bool) {
        widgets.removeAll { $0 == widget }
        if on { widgets = NotchWidget.allCases.filter { $0 == widget || widgets.contains($0) } }
    }
}

public struct NotchSettingsStore {
    private let defaults: UserDefaults
    private let key = "notch.settings"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> NotchSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(NotchSettings.self, from: data) else { return NotchSettings() }
        return settings
    }

    public func save(_ settings: NotchSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
