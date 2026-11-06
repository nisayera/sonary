import Foundation
import SonaryCore

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
    /// Reverses a sideways wheel (or tilting the wheel) on its own.
    public var reverseHorizontalScroll = false
    /// While this key is held, the wheel zooms instead of scrolling.
    public var zoomModifier: ScrollModifier = .none
    public var disableAcceleration = false
    public var buttonMappings: [ButtonMapping] = []
    public var clickFilterMilliseconds = 0
    /// While this key is held, the wheel scrolls sideways.
    public var horizontalScrollModifier: ScrollModifier = .none
    /// A three-finger press on the trackpad posts a middle click instead.
    public var threeFingerMiddleClick = false
    /// Holding an extra button and pushing the mouse runs an action.
    public var gestureMappings: [GestureMapping] = []
    /// What a sideways wheel does, if the mouse has one.
    public var sideWheelLeft: ButtonAction = .none
    public var sideWheelRight: ButtonAction = .none
    public var appOverrides: [String: AppOverride] = [:]

    public init() {}
}

public struct MouseSettingsStore {
    private let defaults: UserDefaults
    private let key = "mouse.settings"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> MouseSettings {
        StoredSettings.load(MouseSettings.self, key: key, from: defaults, fallback: MouseSettings())
    }

    public func save(_ settings: MouseSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
