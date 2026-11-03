import AppKit
import Observation
import SonaryCore

public struct DisplaySettings: Codable, Equatable, Sendable {
    public var shortcuts = true
    /// Remembered software brightness per display, so an overlay survives a restart.
    public var softwareBrightness: [String: Double] = [:]

    public init() {}
}

/// Brightness for every display: the hardware control where macOS offers one, a dimming
/// overlay everywhere else.
@MainActor
@Observable
public final class DisplayModel {
    public private(set) var displays: [DisplayInfo] = []
    public private(set) var settings: DisplaySettings

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var overlays: [CGDirectDisplayID: NSWindow] = [:]
    @ObservationIgnored private var hotKeys: [HotKey] = []
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var running = false

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "display.settings"),
           let settings = try? JSONDecoder().decode(DisplaySettings.self, from: data) {
            self.settings = settings
        } else {
            settings = DisplaySettings()
        }
    }

    func start() {
        running = true
        refresh()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        applyShortcuts()
    }

    func stop() {
        running = false
        applyShortcuts()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for window in overlays.values { window.orderOut(nil) }
        overlays.removeAll()
    }

    public func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let hardware = DisplayServicesBridge.brightness(of: id)
            let software = settings.softwareBrightness[String(id)] ?? 1
            return DisplayInfo(id: id, name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                               hasHardwareControl: hardware != nil, brightness: hardware ?? software)
        }
        for display in displays where !display.hasHardwareControl {
            applyOverlay(to: display.id, brightness: display.brightness)
        }
    }

    public func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        let brightness = clampedBrightness(value)
        if DisplayServicesBridge.setBrightness(brightness, of: id) {
            update(id: id, brightness: brightness)
            return
        }
        update(id: id, brightness: brightness)
        applyOverlay(to: id, brightness: brightness)
        var settings = settings
        settings.softwareBrightness[String(id)] = brightness
        save(settings)
    }

    /// Steps the display the pointer is on, like the brightness keys do.
    public func step(up: Bool) {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = displays.first(where: { $0.id == number.uint32Value }) else { return }
        setBrightness(steppedBrightness(display.brightness, up: up), for: display.id)
    }

    public func update(_ change: (inout DisplaySettings) -> Void) {
        var settings = settings
        change(&settings)
        save(settings)
        applyShortcuts()
    }

    private func save(_ settings: DisplaySettings) {
        self.settings = settings
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "display.settings") }
    }

    private func update(id: CGDirectDisplayID, brightness: Double) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[index].brightness = brightness
    }

    private func applyShortcuts() {
        hotKeys.forEach { $0.unregister() }
        hotKeys = []
        guard running, settings.shortcuts else { return }
        // ⌃⌥⇧↑ and ⌃⌥⇧↓; the plain ⌃⌥ arrows already move windows.
        let modifiers = 4096 | 2048 | 512
        for (code, up) in [(126, true), (125, false)] {
            if let key = HotKey(keyCode: code, modifiers: modifiers, action: { [weak self] in self?.step(up: up) }) {
                hotKeys.append(key)
            }
        }
    }

    /// A black window over the display, as dark as the wanted brightness; clicks go straight through it.
    private func applyOverlay(to id: CGDirectDisplayID, brightness: Double) {
        let alpha = overlayAlpha(for: brightness)
        guard alpha > 0.001 else {
            overlays[id]?.orderOut(nil)
            overlays[id] = nil
            return
        }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }) else { return }
        let window = overlays[id] ?? makeOverlay()
        window.setFrame(screen.frame, display: false)
        window.alphaValue = alpha
        window.orderFrontRegardless()
        overlays[id] = window
    }

    private func makeOverlay() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }
}
