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
    /// How finely the brightness shortcuts step.
    public var stepSize: BrightnessStepSize = .normal
    /// Stepping down past the display's minimum keeps going with an overlay.
    public var dimBelowMinimum = false
    /// The user's own folders of desktop pictures, besides the system's.
    public var wallpaperFolders: [String] = []
    /// The last brightness sent over DDC per display, for monitors that cannot be read back.
    public var ddcBrightness: [String: Double] = [:]

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
    /// How far below its minimum each hardware display is dimmed, 0 to 1. Not kept across
    /// restarts: a display should never wake up darker than its own minimum.
    public private(set) var belowMinimum: [CGDirectDisplayID: Double] = [:]
    /// Regular external monitors, which macOS's own brightness control does not reach, are
    /// driven over DDC/CI as their own buttons are.
    @ObservationIgnored private let ddc = DDCController()
    /// Displays already asked over DDC. Cleared when the set of screens changes, so a monitor is
    /// not probed every time the panel opens.
    @ObservationIgnored private var ddcProbed: Set<CGDirectDisplayID> = []
    /// The last level sent over DDC, for monitors that accept writes but never answer a read.
    @ObservationIgnored private var ddcLevels: [CGDirectDisplayID: Double] = [:]

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = StoredSettings.load(DisplaySettings.self, key: "display.settings", from: defaults,
                                       fallback: DisplaySettings())
    }

    func start() {
        running = true
        refresh()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.ddcProbed.removeAll()
                    self?.refresh()
                }
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
        belowMinimum.removeAll()
        extraLight.removeAll()
    }

    public func refresh() {
        var unprobed: [CGDirectDisplayID] = []
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let hardware = DisplayServicesBridge.brightness(of: id)
            let software = settings.softwareBrightness[String(id)] ?? 1
            // The system answers for the built-in panel and Apple displays; every other external
            // monitor is asked over DDC, once per arrangement of screens.
            if hardware == nil, !isBuiltIn {
                if ddc.hasRoute(id) {
                    return DisplayInfo(id: id, name: screen.localizedName, isBuiltIn: false,
                                       hasHardwareControl: true, brightness: ddcLevels[id] ?? 1)
                }
                if !ddcProbed.contains(id) { unprobed.append(id) }
            }
            return DisplayInfo(id: id, name: screen.localizedName, isBuiltIn: isBuiltIn,
                               hasHardwareControl: hardware != nil, brightness: hardware ?? software)
        }
        ddc.keepOnly(Set(displays.map(\.id)))
        if running, !unprobed.isEmpty {
            ddcProbed.formUnion(unprobed)
            ddc.discover(unprobed) { [weak self] found in
                Task { @MainActor in self?.adoptDDC(found) }
            }
        }
        for display in displays {
            if !display.hasHardwareControl {
                applyOverlay(to: display.id, brightness: display.brightness)
            } else {
                applyOverlay(to: display.id, brightness: 1 - (belowMinimum[display.id] ?? 0))
            }
        }
        applyExtraBrightness()
    }

    /// Moves the monitors DDC reaches off the dimming overlay and onto their own backlight.
    private func adoptDDC(_ found: [CGDirectDisplayID: DDCController.Probe]) {
        guard running, !found.isEmpty else { return }
        for (id, probe) in found {
            switch probe {
            case let .readable(level):
                ddcLevels[id] = level
            case .writeOnly:
                // Never answers a read: start from the level last sent, or the middle.
                ddcLevels[id] = ddcLevels[id] ?? settings.ddcBrightness[String(id)] ?? 0.5
            }
        }
        refresh()
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
        if ddc.hasRoute(id) {
            ddc.setBrightness(brightness, for: id)
            ddcLevels[id] = brightness
            update(id: id, brightness: brightness)
            if belowMinimum[id] != nil, brightness > 0 { setBelowMinimum(0, for: id) }
            var settings = settings
            settings.ddcBrightness[String(id)] = brightness
            save(settings)
            return
        }
        if DisplayServicesBridge.setBrightness(brightness, of: id) {
            update(id: id, brightness: brightness)
            if belowMinimum[id] != nil, brightness > 0 { setBelowMinimum(0, for: id) }
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
        let steps = settings.stepSize.rawValue
        // Below the minimum only makes sense where the hardware has one; an overlay-only
        // display already goes as dark as the overlay allows.
        let canGoBelow = settings.dimBelowMinimum && display.hasHardwareControl
        let level = display.brightness > 0 ? display.brightness : -(belowMinimum[display.id] ?? 0)
        let next = steppedLevel(level, up: up, steps: steps, belowMinimum: canGoBelow)
        if next < 0 {
            if display.brightness > 0 { setBrightness(0, for: display.id) }
            setBelowMinimum(-next, for: display.id)
        } else {
            setBelowMinimum(0, for: display.id)
            setBrightness(next, for: display.id)
        }
    }

    /// Darkens a hardware display past its minimum with an overlay, or lifts that again.
    public func setBelowMinimum(_ amount: Double, for id: CGDirectDisplayID) {
        let amount = min(max(amount, 0), 1)
        if amount > 0 { belowMinimum[id] = amount } else { belowMinimum[id] = nil }
        applyOverlay(to: id, brightness: 1 - amount)
    }

    public func update(_ change: (inout DisplaySettings) -> Void) {
        var settings = settings
        change(&settings)
        save(settings)
        applyShortcuts()
        if !settings.dimBelowMinimum {
            for id in belowMinimum.keys { setBelowMinimum(0, for: id) }
        }
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
