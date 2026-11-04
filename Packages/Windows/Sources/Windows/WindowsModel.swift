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
    /// Snap a window by dragging it against an edge or a corner of the screen.
    public var edgeSnapping = true
    /// Hand the focus to whatever the pointer rests on.
    public var focusFollowsMouse = false
    /// Live pictures of each window in the switcher; needs the Screen Recording permission.
    public var switcherPreviews = false
    /// What a click on a running app's Dock icon does.
    public var dockClickAction: DockClickAction = .system
    /// Show the app's windows, across every Space, when the pointer rests on its Dock icon.
    public var dockPreviews = false
    /// Press a protected shortcut twice, or hold it down.
    public var quitConfirmation: QuitConfirmation = .pressTwice

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
    @ObservationIgnored private var quitTap: CFMachPort?
    @ObservationIgnored private var quitSource: CFRunLoopSource?
    @ObservationIgnored private var quitGuard = QuitGuard()
    @ObservationIgnored private var holdGuard = HoldGuard()
    @ObservationIgnored private var hudProgress: Double = 0
    /// The frame a window had before the last layout, so it can be put back.
    @ObservationIgnored private var previousFrames: [pid_t: CGRect] = [:]
    @ObservationIgnored private var windowCounts: [Int32: Int] = [:]
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var dragMonitor: Any?
    @ObservationIgnored private var upMonitor: Any?
    @ObservationIgnored private var moveMonitor: Any?
    @ObservationIgnored private var snapPreview: NSPanel?
    @ObservationIgnored private var pendingSnap: LayoutAction?
    @ObservationIgnored private var focusState = FocusFollowState()
    @ObservationIgnored private var dockHoverMonitor: Any?
    @ObservationIgnored private var dockClickMonitor: Any?
    @ObservationIgnored private var dockHover = DockHoverState()
    @ObservationIgnored private let dockPreview = DockPreviewController()
    /// The window each app's Dock icon last raised, so a second click moves on.
    @ObservationIgnored private var lastRaisedDockWindow: [Int32: UInt32] = [:]
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

    private static let ctrlOpt = KeyModifier.control | KeyModifier.option

    /// Every window shortcut, for the central shortcut page.
    static var shortcutDefinitions: [ShortcutDefinition] {
        let group = String(localized: "Windows", bundle: .module)
        var list = LayoutAction.allCases.map {
            ShortcutDefinition(id: "windows.layout.\($0.rawValue)", title: layoutName($0), group: group,
                               defaultCombo: KeyCombo(keyCode: $0.keyCode, modifiers: ctrlOpt))
        }
        list += [
            ShortcutDefinition(id: "windows.switcher", title: String(localized: "Window switcher", bundle: .module),
                               group: group, defaultCombo: KeyCombo(keyCode: 48, modifiers: ctrlOpt)),
            ShortcutDefinition(id: "windows.restore",
                               title: String(localized: "Put the last window back", bundle: .module),
                               group: group, defaultCombo: KeyCombo(keyCode: 51, modifiers: ctrlOpt)),
            ShortcutDefinition(id: "windows.nextScreen",
                               title: String(localized: "Move to the next display", bundle: .module),
                               group: group, defaultCombo: KeyCombo(keyCode: 42, modifiers: ctrlOpt)),
        ]
        return list
    }

    private func apply() {
        let shortcuts = ShortcutStore.shared
        shortcuts.describe(Self.shortcutDefinitions)
        shortcuts.unbindAll(prefix: "windows.")
        if running, settings.layoutShortcuts {
            for action in LayoutAction.allCases {
                shortcuts.bind("windows.layout.\(action.rawValue)") { [weak self] in self?.perform(action) }
            }
        }
        if running, settings.windowSwitcher {
            shortcuts.bind("windows.switcher") { [weak self] in self?.showSwitcher() }
        }
        if running {
            shortcuts.bind("windows.restore") { [weak self] in self?.restorePrevious() }
            shortcuts.bind("windows.nextScreen") { [weak self] in self?.moveToNextScreen() }
        }
        if running, settings.quitProtection || settings.closeProtection { installQuitTap() } else { removeQuitTap() }
        if running, settings.quitWhenLastWindowCloses { startWatchingWindows() } else { stopWatchingWindows() }
        if running, settings.edgeSnapping { startEdgeSnapping() } else { stopEdgeSnapping() }
        if running, settings.focusFollowsMouse { startFocusFollowsMouse() } else { stopFocusFollowsMouse() }
        if running, settings.dockPreviews { startDockHover() } else { stopDockHover() }
        if running, settings.dockClickAction != .system { startDockClicks() } else { stopDockClicks() }
        switcher.showsPreviews = settings.switcherPreviews
        if !running || !settings.windowSwitcher { switcher.close() }
    }

    public func showSwitcher() { switcher.show() }

    // MARK: Spaces

    /// Whether the Spaces keep the order you put them in.
    public var spacesKeepTheirOrder: Bool { spaceOrderIsFixed(rearrangesAutomatically: SpaceOrder.rearrangesAutomatically) }

    /// Fixes or releases the Spaces order. The Dock is restarted, which blinks it once.
    public func setSpacesKeepTheirOrder(_ fixed: Bool) {
        SpaceOrder.setRearrangesAutomatically(!fixed)
    }

    // MARK: Snap to the screen edges

    private func startEdgeSnapping() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropped() }
        }
    }

    private func stopEdgeSnapping() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        dragMonitor = nil
        upMonitor = nil
        hideSnapPreview()
        pendingSnap = nil
    }

    private func dragged() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        guard let action = edgeLayout(for: point, in: screen.visibleFrame) else {
            pendingSnap = nil
            hideSnapPreview()
            return
        }
        pendingSnap = action
        showSnapPreview(layoutFrame(action, visible: screen.visibleFrame, current: .zero))
    }

    private func dropped() {
        defer {
            pendingSnap = nil
            hideSnapPreview()
        }
        guard let action = pendingSnap else { return }
        perform(action)
    }

    /// A translucent rectangle showing where the window will land.
    private func showSnapPreview(_ frame: CGRect) {
        let panel = snapPreview ?? {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: SnapPreviewView())
            return panel
        }()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        snapPreview = panel
    }

    private func hideSnapPreview() {
        snapPreview?.orderOut(nil)
        snapPreview = nil
    }

    // MARK: The Dock

    private func startDockHover() {
        guard dockHoverMonitor == nil else { return }
        dockHoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMovedOverDock() }
        }
    }

    private func stopDockHover() {
        if let dockHoverMonitor { NSEvent.removeMonitor(dockHoverMonitor) }
        dockHoverMonitor = nil
        dockHover = DockHoverState()
        dockPreview.close()
    }

    private func startDockClicks() {
        guard dockClickMonitor == nil else { return }
        dockClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dockClicked() }
        }
    }

    private func stopDockClicks() {
        if let dockClickMonitor { NSEvent.removeMonitor(dockClickMonitor) }
        dockClickMonitor = nil
    }

    private func pointerMovedOverDock() {
        let point = NSEvent.mouseLocation
        let app = DockReader.app(at: point)
        guard let pid = dockHover.pointer(over: app?.processIdentifier, at: Date().timeIntervalSinceReferenceDate) else {
            if app == nil { dockPreview.close() }
            return
        }
        guard let app, app.processIdentifier == pid else { return }
        let windows = Self.windows(of: pid)
        guard !windows.isEmpty else { return }
        dockPreview.show(app: app, windows: windows, near: point) { [weak self] window in
            self?.raise(windowID: window.id, pid: pid)
        }
    }

    /// A click on a Dock icon, after the Dock has had it: Sonary adds what the user
    /// asked for rather than swallowing the click, so the Dock keeps working.
    private func dockClicked() {
        let point = NSEvent.mouseLocation
        guard let app = DockReader.app(at: point) else { return }
        let pid = app.processIdentifier
        switch settings.dockClickAction {
        case .system: return
        case .minimizeAll: minimizeWindows(of: pid)
        case .showAllWindows: showAllWindows(of: pid)
        case .cycleWindows:
            let windows = Self.windows(of: pid)
            guard let next = nextWindowToRaise(after: lastRaisedDockWindow[pid], in: windows) else { return }
            lastRaisedDockWindow[pid] = next.id
            raise(windowID: next.id, pid: pid)
        }
    }

    /// Every window of an app, across all Spaces.
    private static func windows(of pid: Int32) -> [DockWindow] {
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return dockWindows(ofPID: pid, in: info)
    }

    /// Brings one window forward. The window server knows it by number, the
    /// accessibility API by position, so the app is activated and its matching window
    /// raised by its frame.
    private func raise(windowID: UInt32, pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.activate()
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return }
        guard let target = Self.windows(of: pid).first(where: { $0.id == windowID }) else { return }
        for window in list where frame(of: window).map({ abs($0.origin.x - target.frame.minX) < 4 }) == true {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return
        }
    }

    private func minimizeWindows(of pid: Int32) {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return }
        for window in list {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private func showAllWindows(of pid: Int32) {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
        for window in list {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    // MARK: Focus follows mouse

    private func startFocusFollowsMouse() {
        guard moveMonitor == nil else { return }
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
    }

    private func stopFocusFollowsMouse() {
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        moveMonitor = nil
        focusState = FocusFollowState()
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return }
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        let windows: [(pid: Int32, frame: CGRect)] = ((raw as? [[String: Any]]) ?? []).compactMap { window in
            guard (window["kCGWindowLayer"] as? Int) == 0,
                  let pid = (window["kCGWindowOwnerPID"] as? NSNumber)?.int32Value,
                  let bounds = window["kCGWindowBounds"] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else { return nil }
            // The window server measures from the top of the primary screen; the pointer does not.
            let frame = cocoaRect(fromAX: CGRect(x: x, y: y, width: width, height: height),
                                  primaryScreenHeight: primary.frame.height)
            return (pid: pid, frame: frame)
        }
        let focused = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let under = windowUnder(point, in: windows)
        guard let pid = focusState.pointer(over: under, at: ProcessInfo.processInfo.systemUptime, focused: focused),
              let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        app.activate()
    }

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
            return axRect(fromCocoa: layoutFrame(action, visible: screen.visibleFrame, full: screen.frame,
                                                 current: current),
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
        // Holding needs the repeats, which is how it knows the keys are still down.
        let wantsRepeats = settings.quitConfirmation == .hold
        guard type == .keyDown, plainCommand, let key, !isRepeat || wantsRepeats,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, bundleID != "com.apple.finder",
              isProtected(bundleID: bundleID, onlyApps: settings.protectedApps) else {
            if type == .keyUp, settings.quitConfirmation == .hold {
                holdGuard.up()
                hideHUD()
            }
            return true
        }
        let now = ProcessInfo.processInfo.systemUptime
        switch settings.quitConfirmation {
        case .pressTwice:
            if quitGuard.shouldQuit(app: bundleID, key: key, at: now) { return true }
            showHUD(appName: app.localizedName ?? bundleID, key: key)
        case .hold:
            if holdGuard.down(app: bundleID, key: key, at: now) {
                holdGuard.up()
                hideHUD()
                return true
            }
            showHUD(appName: app.localizedName ?? bundleID, key: key,
                    progress: holdGuard.progress(app: bundleID, key: key, at: now))
        }
        return false
    }

    /// The hint while a protected shortcut waits. With a progress value it shows a bar
    /// filling up, so holding has something to look at.
    private func showHUD(appName: String, key: ProtectedKey, progress: Double? = nil) {
        let text = hudText(appName: appName, key: key, holding: progress != nil)
        // While holding, the panel is only rebuilt once; after that the bar is updated.
        if let progress, let existing = hud, existing.identifier?.rawValue == text {
            hudProgress = progress
            return
        }
        hud?.orderOut(nil)
        hudProgress = progress ?? 0
        let view = QuitHintView(text: text, progress: progress == nil ? nil : { [weak self] in self?.hudProgress ?? 0 })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.identifier = NSUserInterfaceItemIdentifier(text)
        panel.contentView = host
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.minY + screen.frame.height * 0.2))
        }
        panel.orderFrontRegardless()
        hud = panel
        guard progress == nil else { return }  // holding takes it away on key-up
        Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(1.6))
            panel?.orderOut(nil)
            if self?.hud === panel { self?.hud = nil }
        }
    }

    private func hideHUD() {
        hud?.orderOut(nil)
        hud = nil
    }

    private func hudText(appName: String, key: ProtectedKey, holding: Bool) -> String {
        switch (key, holding) {
        case (.quit, false): String(localized: "Press ⌘Q again to quit \(appName)", bundle: .module)
        case (.close, false): String(localized: "Press ⌘W again to close this window", bundle: .module)
        case (.quit, true): String(localized: "Hold ⌘Q to quit \(appName)", bundle: .module)
        case (.close, true): String(localized: "Hold ⌘W to close this window", bundle: .module)
        }
    }
}
