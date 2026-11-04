import AppKit
import CoreGraphics
import Observation
import SonaryCore

public struct DisplaySettings: Codable, Equatable, Sendable {
    public var shortcuts = true
    /// Remembered software brightness per display, so an overlay survives a restart.
    public var softwareBrightness: [String: Double] = [:]
    /// Switch Bluetooth off when the Mac sleeps and back on when it wakes.
    public var bluetoothOffDuringSleep = false
    /// Extra brightness per display, 0…1, on panels that have headroom above white.
    public var extraBrightness: [String: Double] = [:]

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
    @ObservationIgnored private let extraLight = ExtraBrightnessOverlay()
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var sleepObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    /// Sonary only switches Bluetooth back on when it was the one that switched it off.
    @ObservationIgnored private var turnedOffBluetooth = false
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
        observeSleep()
    }

    /// Bluetooth is switched off on sleep and restored on wake, and only then.
    private func observeSleep() {
        guard sleepObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bluetoothForSleep() }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification,
                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bluetoothForWake() }
        }
    }

    private func bluetoothForSleep() {
        guard settings.bluetoothOffDuringSleep, BluetoothPower.isOn == true else { return }
        turnedOffBluetooth = BluetoothPower.set(on: false)
    }

    private func bluetoothForWake() {
        guard shouldRestoreBluetooth(turnedOffBySonary: turnedOffBluetooth,
                                     settingEnabled: settings.bluetoothOffDuringSleep) else { return }
        BluetoothPower.set(on: true)
        turnedOffBluetooth = false
    }

    /// Whether this Mac lets Sonary switch Bluetooth at all.
    public var canSwitchBluetooth: Bool { BluetoothPower.isAvailable }

    func stop() {
        running = false
        applyShortcuts()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        if let sleepObserver { workspace.removeObserver(sleepObserver) }
        if let wakeObserver { workspace.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
        for window in overlays.values { window.orderOut(nil) }
        overlays.removeAll()
        extraLight.removeAll()
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
        applyExtraBrightness()
    }

    // MARK: Extra brightness

    /// How much headroom above white each display has, by its identifier. Empty for
    /// panels that have none, which is most of them.
    public var extraBrightnessCapable: Set<CGDirectDisplayID> {
        var result: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  extraBrightnessHeadroom(
                    maxPotentialEDR: screen.maximumPotentialExtendedDynamicRangeColorComponentValue) > 0
            else { continue }
            result.insert(CGDirectDisplayID(number.uint32Value))
        }
        return result
    }

    public func extraBrightness(for id: CGDirectDisplayID) -> Double {
        settings.extraBrightness[String(id)] ?? 0
    }

    public func setExtraBrightness(_ amount: Double, for id: CGDirectDisplayID) {
        update { $0.extraBrightness[String(id)] = min(max(amount, 0), 1) }
        applyExtraBrightness()
    }

    private func applyExtraBrightness() {
        guard running else { return extraLight.removeAll() }
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            extraLight.apply(amount: extraBrightness(for: id), to: screen, id: id)
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

    // ⌃⌥⇧↑ and ⌃⌥⇧↓; the plain ⌃⌥ arrows already move windows.
    private static let brightnessModifiers = KeyModifier.control | KeyModifier.option | KeyModifier.shift

    static var shortcutDefinitions: [ShortcutDefinition] { [
        ShortcutDefinition(id: "display.brighter", title: String(localized: "Brighter", bundle: .module),
                           group: String(localized: "Display", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 126, modifiers: DisplayModel.brightnessModifiers)),
        ShortcutDefinition(id: "display.darker", title: String(localized: "Darker", bundle: .module),
                           group: String(localized: "Display", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 125, modifiers: DisplayModel.brightnessModifiers)),
    ] }

    private func applyShortcuts() {
        let shortcuts = ShortcutStore.shared
        shortcuts.describe(Self.shortcutDefinitions)
        shortcuts.unbindAll(prefix: "display.")
        guard running, settings.shortcuts else { return }
        shortcuts.bind("display.brighter") { [weak self] in self?.step(up: true) }
        shortcuts.bind("display.darker") { [weak self] in self?.step(up: false) }
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
