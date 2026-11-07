import AppKit
import CoreGraphics

// MARK: The system's own switcher

/// Reads and switches the window server's own shortcuts.
public protocol SystemHotKeyControlling: Sendable {
    /// Nil when the call is missing on this macOS.
    func isEnabled(_ id: Int32) -> Bool?
    func setEnabled(_ id: Int32, _ enabled: Bool) -> Bool
}

/// The window server's shortcut table. The calls are private SkyLight functions, looked up at
/// runtime, so a macOS without them leaves the system switcher alone instead of crashing.
public struct WindowServerHotKeys: SystemHotKeyControlling {
    private typealias SetFunction = @convention(c) (Int32, Bool) -> CGError
    private typealias IsFunction = @convention(c) (Int32) -> Bool

    public init() {}

    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }  // RTLD_DEFAULT
        return unsafeBitCast(pointer, to: type)
    }

    public func isEnabled(_ id: Int32) -> Bool? {
        symbol("CGSIsSymbolicHotKeyEnabled", as: IsFunction.self).map { $0(id) }
    }

    public func setEnabled(_ id: Int32, _ enabled: Bool) -> Bool {
        guard let set = symbol("CGSSetSymbolicHotKeyEnabled", as: SetFunction.self) else { return false }
        return set(id, enabled) == .success
    }
}

/// The system's ⌘Tab (1) and ⌘⇧Tab (2), as the window server numbers them.
public let nativeSwitcherHotKeys: [Int32] = [1, 2]

/// Switches the system's ⌘Tab off while Sonary's switcher has it, and always back on, also
/// after a crash: the state before is written down before anything changes, and the next
/// start puts it back.
public final class NativeSwitcherGuard: @unchecked Sendable {
    private let control: any SystemHotKeyControlling
    private let defaults: UserDefaults
    private let key = "windows.nativeSwitcher.original"
    private let lock = NSLock()

    public init(control: any SystemHotKeyControlling, defaults: UserDefaults) {
        self.control = control
        self.defaults = defaults
    }

    /// False when the window server calls are missing; the system switcher then stays on.
    @discardableResult
    public func takeOver() -> Bool {
        lock.withLock {
            if defaults.object(forKey: key) == nil {
                var original: [String: Bool] = [:]
                for id in nativeSwitcherHotKeys {
                    guard let enabled = control.isEnabled(id) else { return false }
                    original[String(id)] = enabled
                }
                defaults.set(original, forKey: key)
            }
            var all = true
            for id in nativeSwitcherHotKeys where !control.setEnabled(id, false) { all = false }
            if !all { restoreLocked() }
            return all
        }
    }

    public func restore() {
        lock.withLock { restoreLocked() }
    }

    /// Call on start: if a previous run left the system switcher off, put it back first.
    public func recoverIfNeeded() { restore() }

    private func restoreLocked() {
        guard let original = defaults.dictionary(forKey: key) as? [String: Bool] else { return }
        var all = true
        for (id, enabled) in original {
            guard let id = Int32(id) else { continue }
            if !control.setEnabled(id, enabled) { all = false }
        }
        if all { defaults.removeObject(forKey: key) }
    }
}

// MARK: Listening for ⌘Tab

private func commandTabCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<CommandTabTap>.fromOpaque(userInfo).takeUnretainedValue()
    // Read the event here; only Sendable values cross into the main actor.
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let keep = MainActor.assumeIsolated { tap.handle(type: type, keyCode: keyCode, flags: flags) }
    return keep ? Unmanaged.passUnretained(event) : nil
}

/// Catches ⌘Tab before the app in front does, and the keys pressed while Sonary's switcher
/// is open. Needs Accessibility.
@MainActor
final class CommandTabTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var tracker = CommandTabTracker()
    /// What the switcher should do. Called after the event has gone, so a slow switcher never
    /// holds up the keyboard.
    var onStep: (CommandTabStep) -> Void = { _ in }

    var isRunning: Bool { port != nil }

    /// False when the tap could not be created, which means Accessibility is missing.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: commandTabCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        tracker.closed()
        return true
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        tracker.closed()
    }

    /// The switcher closed on its own, by a click or because there was nothing to show.
    func closed() { tracker.closed() }

    /// True to let the event through.
    func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return true
        case .keyDown:
            let step = tracker.keyDown(keyCode: keyCode, command: flags.contains(.maskCommand),
                                       shift: flags.contains(.maskShift), option: flags.contains(.maskAlternate),
                                       control: flags.contains(.maskControl))
            if step == .pass { return true }
            send(step)
            return false
        case .keyUp:
            return tracker.keyUp(keyCode: keyCode) == .pass
        case .flagsChanged:
            // Modifier changes always go on, so apps never see a ⌘ stuck down.
            send(tracker.flagsChanged(command: flags.contains(.maskCommand)))
            return true
        default:
            return true
        }
    }

    private func send(_ step: CommandTabStep) {
        guard step != .pass, step != .swallow else { return }
        Task { @MainActor in self.onStep(step) }
    }
}
