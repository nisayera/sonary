import Foundation

public struct AppOverride: Codable, Equatable, Sendable {
    public var disabled: Bool
    public var linearScroll: Bool?
    public var smoothScroll: Bool?
    public var reverseScroll: Bool?

    public init(disabled: Bool = false, linearScroll: Bool? = nil, smoothScroll: Bool? = nil, reverseScroll: Bool? = nil) {
        self.disabled = disabled
        self.linearScroll = linearScroll
        self.smoothScroll = smoothScroll
        self.reverseScroll = reverseScroll
    }
}

public struct MouseSettings: Codable, Equatable, Sendable {
    public var linearScroll = false
    public var scrollLinesPerStep = 3
    public var smoothScroll = false
    public var smoothness = 0.5
    public var reverseScroll = false
    public var disableAcceleration = false
    public var buttonMappings: [ButtonMapping] = []
    public var clickFilterMilliseconds = 0
    public var appOverrides: [String: AppOverride] = [:]

    public init() {}
}

public struct MouseSettingsStore {
    private let defaults: UserDefaults
    private let key = "mouse.settings"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> MouseSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(MouseSettings.self, from: data) else {
            return MouseSettings()
        }
        return settings
    }

    public func save(_ settings: MouseSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
