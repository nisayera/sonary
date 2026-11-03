import AppKit
import IOKit.hidsystem
import Observation
import SonaryCore

private func keyboardTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let model = Unmanaged<KeyboardModel>.fromOpaque(userInfo).takeUnretainedValue()
    // Only Sendable values cross to the main actor; CGEvent stays on the tap thread.
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let outcome = MainActor.assumeIsolated { model.decide(type: type, keyCode: keyCode, flags: flags) }
    switch outcome {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow, .tap:
        return nil
    case .hyper:
        event.flags = flags.union([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        return Unmanaged.passUnretained(event)
    }
}

/// The Super Key: one key becomes ⌃⌥⇧⌘ while held, and runs a small action when tapped.
@MainActor
@Observable
public final class KeyboardModel {
    public private(set) var settings: KeyboardSettings
    /// Set while the Super Key is held, so the settings screen can show it working.
    public private(set) var isHolding = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var engine = SuperKeyEngine()
    @ObservationIgnored private var debouncer = KeyDebouncer(milliseconds: 0)
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var running = false
    /// Called when the Super Key is tapped and the action is "command bar".
    @ObservationIgnored public var commandBarAction: (() -> Void)?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "keyboard.settings"),
           let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data) {
            self.settings = settings
        } else {
            settings = KeyboardSettings()
        }
    }

    func start() {
        running = true
        apply()
    }

    func stop() {
        running = false
        apply()
    }

    public func update(_ change: (inout KeyboardSettings) -> Void) {
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "keyboard.settings") }
        apply()
    }

    private func apply() {
        engine.reset()
        isHolding = false
        debouncer = KeyDebouncer(milliseconds: settings.debounceMilliseconds)
        let wanted = running && (settings.superKeyEnabled || settings.debounceMilliseconds > 0)
        if wanted { installTap() } else { removeTap() }
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: keyboardTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    func decide(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> SuperKeyOutcome {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            engine.reset()
            isHolding = false
            return .pass
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if type == .keyDown, settings.debounceMilliseconds > 0,
           debouncer.shouldDrop(keyCode: keyCode, timestampNanoseconds: UInt64(max(0, ProcessInfo.processInfo.systemUptime) * 1_000_000_000)) {
            return .swallow
        }
        guard superKeyActive(settings, bundleID: frontmost) else { return .pass }
        let now = ProcessInfo.processInfo.systemUptime
        if keyCode == settings.source.keyCode, type == .flagsChanged {
            let pressed = isPressed(flags: flags)
            let outcome = pressed ? engine.sourcePressed(at: now) : engine.sourceReleased(at: now)
            isHolding = engine.isHolding
            if settings.source == .capsLock { turnCapsLockOff() }
            if outcome == .tap { runTapAction() }
            return outcome
        }
        guard type == .keyDown else { return .pass }
        let outcome = engine.otherKeyPressed()
        return outcome
    }

    /// Caps Lock reports its state in the flags, the other sources report their own modifier bit.
    private func isPressed(flags: CGEventFlags) -> Bool {
        switch settings.source {
        case .capsLock: flags.contains(.maskAlphaShift)
        case .rightCommand: flags.contains(.maskCommand)
        case .rightOption: flags.contains(.maskAlternate)
        case .rightControl: flags.contains(.maskControl)
        }
    }

    /// Keeps Caps Lock from actually switching on while it serves as the Super Key.
    private func turnCapsLockOff() {
        var connect: io_connect_t = 0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, task_self_trap(), UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), false)
    }

    private func runTapAction() {
        switch settings.tapAction {
        case .none: break
        case .escape: postEscape()
        case .commandBar: commandBarAction?()
        }
    }

    private func postEscape() {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)
            event?.post(tap: .cghidEventTap)
        }
    }
}
