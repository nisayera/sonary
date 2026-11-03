import AppKit
import Observation
import SonaryCore
import SwiftUI

public struct WindowsSettings: Codable, Equatable, Sendable {
    public var layoutShortcuts = true
    public var quitProtection = false
    public var closeProtection = false
    /// Empty means every app; otherwise only these bundle IDs are protected.
    public var protectedApps: [String] = []
    public var windowSwitcher = true
    /// Quit an app once its last window is closed.
    public var quitWhenLastWindowCloses = false
    /// Apps this never applies to, by bundle ID.
    public var neverQuitApps: [String] = []

    public init() {}
}

private func quitTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let model = Unmanaged<WindowsModel>.fromOpaque(userInfo).takeUnretainedValue()
    // Read the event on the tap thread; only Sendable values cross into the main actor.
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let pass = MainActor.assumeIsolated {
        model.shouldPass(type: type, flags: flags, keyCode: keyCode, isRepeat: isRepeat)
    }
    return pass ? Unmanaged.passUnretained(event) : nil
}

/// Window layouts on ⌃⌥ shortcuts and the "press ⌘Q twice" quit protection.
@MainActor
@Observable
public final class WindowsModel {
    public private(set) var settings: WindowsSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hotKeys: [HotKey] = []
    @ObservationIgnored private var quitTap: CFMachPort?
    @ObservationIgnored private var quitSource: CFRunLoopSource?
    @ObservationIgnored private var quitGuard = QuitGuard()
    /// The frame a window had before the last layout, so it can be put back.
    @ObservationIgnored private var previousFrames: [pid_t: CGRect] = [:]
    @ObservationIgnored private var windowCounts: [Int32: Int] = [:]
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var hud: NSPanel?
    @ObservationIgnored private let switcher = WindowSwitcherController()
    @ObservationIgnored private var running = false

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "windows.settings"),
           let settings = try? JSONDecoder().decode(WindowsSettings.self, from: data) {
            self.settings = settings
        } else {
            settings = WindowsSettings()
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

    public func update(_ change: (inout WindowsSettings) -> Void) {
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "windows.settings") }
        apply()
    }

    private func apply() {
        hotKeys.forEach { $0.unregister() }
        hotKeys = []
        if running, settings.layoutShortcuts {
            for action in LayoutAction.allCases {
                // ⌃⌥ = controlKey 4096 + optionKey 2048
                if let key = HotKey(keyCode: action.keyCode, modifiers: 4096 | 2048, action: { [weak self] in self?.perform(action) }) {
                    hotKeys.append(key)
                }
            }
        }
        if running, settings.windowSwitcher,
           // ⌃⌥Tab (key code 48)
           let key = HotKey(keyCode: 48, modifiers: 4096 | 2048, action: { [weak self] in self?.showSwitcher() }) {
            hotKeys.append(key)
        }
        if running,
           // ⌃⌥⌫ puts the last moved window back (key code 51)
           let key = HotKey(keyCode: 51, modifiers: 4096 | 2048, action: { [weak self] in self?.restorePrevious() }) {
            hotKeys.append(key)
        }
        if running,
           // ⌃⌥→| moves the window to the next display (key code 42, the backslash key)
           let key = HotKey(keyCode: 42, modifiers: 4096 | 2048, action: { [weak self] in self?.moveToNextScreen() }) {
            hotKeys.append(key)
        }
        if running, settings.quitProtection || settings.closeProtection { installQuitTap() } else { removeQuitTap() }
        if running, settings.quitWhenLastWindowCloses { startWatchingWindows() } else { stopWatchingWindows() }
        if !running || !settings.windowSwitcher { switcher.close() }
    }

    public func showSwitcher() { switcher.show() }

    // MARK: Quit when the last window closes

    private func startWatchingWindows() {
        guard watchTask == nil else { return }
        windowCounts = currentWindowCounts()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.checkWindows()
            }
        }
    }

    private func stopWatchingWindows() {
        watchTask?.cancel()
        watchTask = nil
        windowCounts = [:]
    }

    private func checkWindows() {
        let current = currentWindowCounts()
        for pid in appsWithNoWindowsLeft(previous: windowCounts, current: current) {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  bundleID != "com.apple.finder",
                  !settings.neverQuitApps.contains(bundleID) else { continue }
            app.terminate()
        }
        windowCounts = current
    }

    /// How many normal windows each running app has on screen.
    private func currentWindowCounts() -> [Int32: Int] {
        var counts: [Int32: Int] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            counts[app.processIdentifier] = 0
        }
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        for window in (raw as? [[String: Any]]) ?? [] {
            guard (window["kCGWindowLayer"] as? Int) == 0,
                  let pid = (window["kCGWindowOwnerPID"] as? NSNumber)?.int32Value,
                  counts[pid] != nil else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    /// Moves the front window to the next display, keeping its relative place and size.
    public func moveToNextScreen() {
        withFrontWindow { window, current, primaryHeight in
            let cocoa = cocoaRect(fromAX: current, primaryScreenHeight: primaryHeight)
            let screens = NSScreen.screens.map(\.visibleFrame)
            guard let target = nextScreen(after: cocoa, screens: screens),
                  let source = screens.first(where: { $0.contains(CGPoint(x: cocoa.midX, y: cocoa.midY)) }) ?? screens.first
            else { return nil }
            return axRect(fromCocoa: movedFrame(cocoa, from: source, to: target), primaryScreenHeight: primaryHeight)
        }
    }

    /// Puts the front window back where it was before the last move.
    public func restorePrevious() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let saved = previousFrames[pid] else { return }
        withFrontWindow { _, _, _ in saved }
        previousFrames[pid] = nil
    }

    // MARK: Layouts

    public func perform(_ action: LayoutAction) {
        withFrontWindow { _, currentAX, height in
            let current = cocoaRect(fromAX: currentAX, primaryScreenHeight: height)
            let center = CGPoint(x: current.midX, y: current.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
            guard let screen else { return nil }
            return axRect(fromCocoa: layoutFrame(action, visible: screen.visibleFrame, current: current),
                          primaryScreenHeight: height)
        }
    }

    /// Runs `newFrame` with the front window's current frame and applies what it returns,
    /// remembering where the window was so it can be put back.
    private func withFrontWindow(_ newFrame: (AXUIElement, CGRect, CGFloat) -> CGRect?) {
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let primary = NSScreen.screens.first else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
        let window = unsafeDowncast(focused, to: AXUIElement.self)
        guard let currentAX = frame(of: window) else { return }
        let height = primary.frame.height
        guard let target = newFrame(window, currentAX, height), target != currentAX else { return }
        previousFrames[app.processIdentifier] = currentAX
        setFrame(target, of: window)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(unsafeDowncast(positionRef, to: AXValue.self), .cgPoint, &point)
        AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func setFrame(_ rect: CGRect, of window: AXUIElement) {
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Position, size, position again: some apps clamp the size against the old position.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    // MARK: Quit protection

    private func installQuitTap() {
        guard quitTap == nil else { return }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: quitTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        quitTap = tap
        quitSource = source
    }

    private func removeQuitTap() {
        if let quitTap { CGEvent.tapEnable(tap: quitTap, enable: false) }
        if let quitSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), quitSource, .commonModes) }
        quitTap = nil
        quitSource = nil
    }

    /// False swallows the key press.
    func shouldPass(type: CGEventType, flags: CGEventFlags, keyCode: Int64, isRepeat: Bool) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let quitTap { CGEvent.tapEnable(tap: quitTap, enable: true) }
            return true
        }
        let plainCommand = flags.contains(.maskCommand)
            && !flags.contains(.maskShift) && !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
        let key: ProtectedKey? = switch keyCode {
        case 12 where settings.quitProtection: .quit
        case 13 where settings.closeProtection: .close
        default: nil
        }
        guard type == .keyDown, plainCommand, let key, !isRepeat,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, bundleID != "com.apple.finder",
              isProtected(bundleID: bundleID, onlyApps: settings.protectedApps) else {
            return true
        }
        if quitGuard.shouldQuit(app: bundleID, key: key, at: ProcessInfo.processInfo.systemUptime) {
            return true
        }
        showHUD(appName: app.localizedName ?? bundleID, key: key)
        return false
    }

    private func showHUD(appName: String, key: ProtectedKey) {
        hud?.orderOut(nil)
        let text = key == .quit
            ? String(localized: "Press ⌘Q again to quit \(appName)", bundle: .module)
            : String(localized: "Press ⌘W again to close this window", bundle: .module)
        let view = Text(text)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: Capsule())
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.contentView = host
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + screen.frame.height * 0.2))
        }
        panel.orderFrontRegardless()
        hud = panel
        Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(1.6))
            panel?.orderOut(nil)
            if self?.hud === panel { self?.hud = nil }
        }
    }
}
