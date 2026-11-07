import Foundation
import SonaryCore

public enum NotchWidget: String, Codable, CaseIterable, Sendable {
    case music, calendar, timer, downloads, batteries, shelf, camera, controls, notes

    public var symbol: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        case .timer: "timer"
        case .downloads: "arrow.down.circle"
        case .batteries: "battery.75percent"
        case .shelf: "tray.full"
        case .camera: "video"
        case .controls: "slider.horizontal.3"
        case .notes: "note.text"
        }
    }
}

public struct NotchSettings: Codable, Equatable, Sendable {
    /// Calendar starts off because it asks for access.
    public var widgets: [NotchWidget] = [.music, .timer, .downloads, .batteries]
    public var showOnScreensWithoutNotch = true
    /// A notice once an accessory's battery falls to 20 %.
    public var lowBatteryWarning = true
    /// The island opens when the pointer rests on it; off, only a click opens it.
    public var openOnHover = true
    /// How long the pointer has to rest before the island opens, in seconds.
    public var hoverDelay = 0.0
    /// The countdowns the timer offers, in minutes.
    public var timerPresets: [Int] = [1, 5, 10, 25]

    public init() {}

    public func isOn(_ widget: NotchWidget) -> Bool { widgets.contains(widget) }

    /// Turning a widget on puts it last, so the order the user chose stays.
    public mutating func set(_ widget: NotchWidget, on: Bool) {
        widgets.removeAll { $0 == widget }
        if on { widgets.append(widget) }
    }

    /// Moves a widget one place towards the front, or the back.
    public mutating func move(_ widget: NotchWidget, forward: Bool) {
        guard let index = widgets.firstIndex(of: widget) else { return }
        let target = forward ? index - 1 : index + 1
        guard widgets.indices.contains(target) else { return }
        widgets.swapAt(index, target)
    }
}

public struct NotchSettingsStore {
    private let defaults: UserDefaults
    private let key = "notch.settings"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> NotchSettings {
        StoredSettings.load(NotchSettings.self, key: key, from: defaults, fallback: NotchSettings())
    }

    public func save(_ settings: NotchSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// The timer's countdowns from what the user typed: whole minutes from 1 to 600, each once,
/// in order, at most five.
public func parseTimerPresets(_ text: String) -> [Int] {
    var seen = Set<Int>()
    let minutes = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
        .compactMap { Int($0) }
        .filter { (1...600).contains($0) && seen.insert($0).inserted }
    return Array(minutes.sorted().prefix(5))
}
