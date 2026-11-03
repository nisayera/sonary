import AppKit
import Observation
import SonaryCore
import SwiftUI

public struct WindowsSettings: Codable, Equatable, Sendable {
    public var layoutShortcuts = true
    public var quitProtection = false

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
    @ObservationIgnored private var hud: NSPanel?
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
        if running, settings.quitProtection { installQuitTap() } else { removeQuitTap() }
    }

    // MARK: Layouts

    public func perform(_ action: LayoutAction) {
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
        let current = cocoaRect(fromAX: currentAX, primaryScreenHeight: height)
        let center = CGPoint(x: current.midX, y: current.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? primary
        let target = layoutFrame(action, visible: screen.visibleFrame, current: current)
        setFrame(axRect(fromCocoa: target, primaryScreenHeight: height), of: window)
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
        let isCommandQ = keyCode == 12
            && flags.contains(.maskCommand)
            && !flags.contains(.maskShift) && !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
        guard type == .keyDown, isCommandQ, !isRepeat,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, bundleID != "com.apple.finder" else {
            return true
        }
        if quitGuard.shouldQuit(app: bundleID, at: ProcessInfo.processInfo.systemUptime) {
            return true
        }
        showHUD(appName: app.localizedName ?? bundleID)
        return false
    }

    private func showHUD(appName: String) {
        hud?.orderOut(nil)
        let text = String(localized: "Press ⌘Q again to quit \(appName)", bundle: .module)
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
