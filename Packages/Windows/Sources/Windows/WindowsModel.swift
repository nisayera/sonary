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
    /// Move or resize the window under the pointer while holding a chosen combination.
    public var modifierDrag: ModifierDragMode = .off
    /// The combination that starts a modifier-drag, as Carbon flags. ⌃⌘ by default.
    public var modifierDragKeys = KeyModifier.control | KeyModifier.command
    /// Apps that keep their own window layout: shortcuts, screen edges and modifier-drag
    /// leave them alone while they are in front.
    public var layoutExcludedApps: [String] = []
    /// While one of these apps is in front, no window pictures are taken (games, video).
    public var previewPausingApps: [String] = []
    /// The green window button fills the screen instead of making a full-screen Space.
    public var greenButtonMaximizes = false
    /// Apps whose green button keeps the macOS behaviour: games, players, emulators.
    public var greenButtonExceptions: [String] = []
    /// A searchable list of windows, or one large icon per app.
    public var switcherStyle: SwitcherStyle = .list
    /// ⌘Tab opens Sonary's switcher; the macOS one is off meanwhile and comes back afterwards.
    public var switcherTakesCommandTab = false

    public init() {}
}

/// Marks the plain ⌘Q or ⌘W that Sonary sends after ⌥ confirmed it, so its own tap lets
/// that one through ("SONY").
let quitTapSyntheticMarker: Int64 = 0x534F_4E59

private func quitTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let model = Unmanaged<WindowsModel>.fromOpaque(userInfo).takeUnretainedValue()
    // Read the event on the tap thread; only Sendable values cross into the main actor.
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let isOurs = event.getIntegerValueField(.eventSourceUserData) == quitTapSyntheticMarker
    let pass = MainActor.assumeIsolated {
        model.shouldPass(type: type, flags: flags, keyCode: keyCode, isRepeat: isRepeat, isSynthetic: isOurs)
    }
    return pass ? Unmanaged.passUnretained(event) : nil
}

private func greenButtonTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let model = Unmanaged<WindowsModel>.fromOpaque(userInfo).takeUnretainedValue()
    let location = event.location
    let option = event.flags.contains(.maskAlternate)
    let pass = MainActor.assumeIsolated {
        model.greenButtonShouldPass(type: type, location: location, option: option)
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
    /// Set when the ⌘Q/⌘W tap could not be created, which means Accessibility is missing.
    public private(set) var quitProtectionNeedsAccessibility = false
    @ObservationIgnored private var hudProgress: Double = 0
    /// The frame a window had before the last layout, so it can be put back.
    @ObservationIgnored private var previousFrames: [pid_t: CGRect] = [:]
    @ObservationIgnored private var quitWatch = QuitWatchState()
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
    @ObservationIgnored private var dockDownMonitor: Any?
    /// The app in front when the last click began, so a Dock click acts only on that one.
    @ObservationIgnored private var frontmostAtMouseDown: Int32?
    @ObservationIgnored private var greenButtonTap: CFMachPort?
    @ObservationIgnored private var greenButtonSource: CFRunLoopSource?
    /// The window whose green button went down; its button-up is swallowed too.
    @ObservationIgnored private var pendingGreenButtonWindow: AXUIElement?
    @ObservationIgnored private var modifierDragMonitor: Any?
    /// The window a modifier-drag grabbed, where it was, and where the pointer began.
    @ObservationIgnored private var modifierDragStart: (window: AXUIElement, frame: CGRect, pointer: CGPoint)?
    @ObservationIgnored private var hud: NSPanel?
    @ObservationIgnored private let switcher = WindowSwitcherController()
    @ObservationIgnored private let commandTab = CommandTabTap()
    @ObservationIgnored private let nativeSwitcher: NativeSwitcherGuard
    @ObservationIgnored private var terminateObserver: (any NSObjectProtocol)?
    /// Set when ⌘Tab could not be taken over because Accessibility is missing.
    public private(set) var commandTabNeedsAccessibility = false
    /// Set when macOS would not switch its own ⌘Tab off, so both switchers would open.
    public private(set) var commandTabKeepsSystemSwitcher = false
    @ObservationIgnored private var running = false

    public init(defaults: UserDefaults, hotKeys: any SystemHotKeyControlling = WindowServerHotKeys()) {
        self.defaults = defaults
        settings = StoredSettings.load(WindowsSettings.self, key: "windows.settings", from: defaults,
                                       fallback: WindowsSettings())
        nativeSwitcher = NativeSwitcherGuard(control: hotKeys, defaults: defaults)
        // Quitting never leaves the Mac without its own ⌘Tab.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [nativeSwitcher] _ in nativeSwitcher.restore() }
    }

    func start() {
        running = true
        // A crash while ⌘Tab was taken over left the system switcher off: put it back first.
        nativeSwitcher.recoverIfNeeded()
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
        var list = LayoutAction.allCases.map { action in
            ShortcutDefinition(id: "windows.layout.\(action.rawValue)", title: layoutName(action), group: group,
                               defaultCombo: action.keyCode.map { KeyCombo(keyCode: $0, modifiers: ctrlOpt) }
                                   ?? KeyCombo.none)
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
        if running, settings.modifierDrag != .off { startModifierDrag() } else { stopModifierDrag() }
        if running, settings.greenButtonMaximizes { installGreenButtonTap() } else { removeGreenButtonTap() }
        switcher.showsPreviews = settings.switcherPreviews
        switcher.style = settings.switcherStyle
        if !running || !settings.windowSwitcher { switcher.close() }
        if running, settings.windowSwitcher, settings.switcherTakesCommandTab { startCommandTab() } else { stopCommandTab() }
    }

    // MARK: ⌘Tab

    private func startCommandTab() {
        switcher.onClose = { [weak self] in self?.commandTab.closed() }
        commandTab.onStep = { [weak self] step in self?.commandTabStep(step) }
        guard commandTab.isRunning || commandTab.start() else {
            commandTabNeedsAccessibility = true
            return
        }
        commandTabNeedsAccessibility = false
        commandTabKeepsSystemSwitcher = !nativeSwitcher.takeOver()
    }

    private func stopCommandTab() {
        commandTab.stop()
        nativeSwitcher.restore()
        commandTabNeedsAccessibility = false
        commandTabKeepsSystemSwitcher = false
    }

    private func commandTabStep(_ step: CommandTabStep) {
        switch step {
        case let .open(forward):
            switcher.showsPreviews = settings.switcherPreviews && !frontAppPausesPreviews
            switcher.showHeld(forward: forward)
        case let .move(forward):
            switcher.move(forward: forward)
        case .choose:
            switcher.chooseSelected()
        case .cancel:
            switcher.close()
        case .pass, .swallow:
            break
        }
    }

    public func showSwitcher() {
        switcher.showsPreviews = settings.switcherPreviews && !frontAppPausesPreviews
        switcher.show()
    }

    /// Every open window, front to back, for the command bar.
    public func openWindows() -> [WindowEntry] {
        WindowSwitcherController.currentEntries()
    }

    /// Brings one of those windows to the front.
    public func raise(_ entry: WindowEntry) {
        WindowSwitcherController.raise(entry)
    }

    /// Whether the app in front keeps its own layout and wants Sonary's hands off.
    private var frontAppKeepsItsLayout: Bool {
        isExcluded(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, in: settings.layoutExcludedApps)
    }

    /// Whether the app in front pauses window pictures.
    private var frontAppPausesPreviews: Bool {
        isExcluded(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, in: settings.previewPausingApps)
    }

    // MARK: Moving a window by holding keys

    private func startModifierDrag() {
        guard modifierDragMonitor == nil else { return }
        modifierDragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .flagsChanged]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.modifierDragged(event) }
        }
    }

    private func stopModifierDrag() {
        if let modifierDragMonitor { NSEvent.removeMonitor(modifierDragMonitor) }
        modifierDragMonitor = nil
        modifierDragStart = nil
    }

    /// While the chosen keys are held, the pointer moves or resizes the window it is
    /// over. Letting the keys go ends it, so an ordinary drag is never disturbed.
    private func modifierDragged(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        let flags = carbonFlags(event.modifierFlags)
        guard isModifierDrag(flags: flags, wanted: settings.modifierDragKeys) else {
            modifierDragStart = nil
            return
        }
        let resizing = event.type == .rightMouseDragged && settings.modifierDrag.resizesOnRight
        guard resizing || settings.modifierDrag.movesOnLeft else { return }

        guard let primary = NSScreen.screens.first else { return }
        guard let start = modifierDragStart else {
            guard let pid = windowUnder(point, in: visibleWindows()),
                  !isExcluded(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                              in: settings.layoutExcludedApps),
                  let window = frontWindow(of: pid), let frame = frame(of: window) else { return }
            modifierDragStart = (window: window, frame: cocoaRect(fromAX: frame,
                                                                  primaryScreenHeight: primary.frame.height),
                                 pointer: point)
            return
        }
        let wanted = resizing
            ? resizedFrame(start: start.frame, from: start.pointer, to: point)
            : draggedFrame(start: start.frame, from: start.pointer, to: point)
        setFrame(axRect(fromCocoa: wanted, primaryScreenHeight: primary.frame.height), of: start.window)
    }

    /// AppKit's modifier flags as the Carbon flags the settings store.
    private func carbonFlags(_ flags: NSEvent.ModifierFlags) -> Int {
        var value = 0
        if flags.contains(.command) { value |= KeyModifier.command }
        if flags.contains(.shift) { value |= KeyModifier.shift }
        if flags.contains(.option) { value |= KeyModifier.option }
        if flags.contains(.control) { value |= KeyModifier.control }
        return value
    }

    // MARK: Spaces

    /// Whether the Spaces keep the order you put them in.
    public var spacesKeepTheirOrder: Bool { spaceOrderIsFixed(rearrangesAutomatically: SpaceOrder.rearrangesAutomatically) }

    /// Fixes or releases the Spaces order. The Dock is restarted, which blinks it once.
    /// Releasing it puts back what was there before Sonary fixed it: when the preference
    /// was never set, it is removed again rather than written as "on".
    public func setSpacesKeepTheirOrder(_ fixed: Bool) {
        let savedKey = "windows.spaces.previous"
        if fixed {
            if defaults.object(forKey: savedKey) == nil {
                defaults.set(encodeSpaceOrderPreference(SpaceOrder.storedValue), forKey: savedKey)
            }
            SpaceOrder.setRearrangesAutomatically(false)
        } else {
            let saved = defaults.object(forKey: savedKey) as? Int
            defaults.removeObject(forKey: savedKey)
            SpaceOrder.restore(decodeSpaceOrderPreference(saved))
        }
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
        guard !frontAppKeepsItsLayout else {
            pendingSnap = nil
            hideSnapPreview()
            return
        }
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
        dockDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.frontmostAtMouseDown = NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
        }
        dockClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dockClicked() }
        }
    }

    private func stopDockClicks() {
        if let dockClickMonitor { NSEvent.removeMonitor(dockClickMonitor) }
        if let dockDownMonitor { NSEvent.removeMonitor(dockDownMonitor) }
        dockClickMonitor = nil
        dockDownMonitor = nil
        frontmostAtMouseDown = nil
    }

    private func pointerMovedOverDock() {
        guard !frontAppPausesPreviews else {
            dockPreview.close()
            return
        }
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
        } act: { [weak self] window, action in
            self?.perform(action, onWindow: window.id, pid: pid)
        }
    }

    /// Closes or minimizes one window from its Dock preview.
    private func perform(_ action: DockWindowAction, onWindow windowID: UInt32, pid: Int32) {
        guard let window = axWindow(matching: windowID, pid: pid) else { return }
        switch action {
        case .close:
            var button: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
                  let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return }
            AXUIElementPerformAction(unsafeDowncast(button, to: AXUIElement.self), kAXPressAction as CFString)
        case .minimize:
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// The accessibility element of a window the window server knows by number, matched
    /// by its frame: the two APIs share no identifier.
    private func axWindow(matching windowID: UInt32, pid: Int32) -> AXUIElement? {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement],
              let target = Self.windows(of: pid).first(where: { $0.id == windowID }) else { return nil }
        return list.first { window in frame(of: window).map { framesMatch($0, target.frame, tolerance: 4) } == true }
    }

    /// A click on a Dock icon, after the Dock has had it: Sonary adds what the user
    /// asked for rather than swallowing the click, so the Dock keeps working.
    private func dockClicked() {
        let point = NSEvent.mouseLocation
        guard let app = DockReader.app(at: point) else { return }
        let pid = app.processIdentifier
        // A click that brought a background app forward was the Dock's; only a click on
        // the app already in front gets the extra action.
        guard dockClickApplies(clickedPID: pid, frontmostAtMouseDown: frontmostAtMouseDown) else { return }
        switch settings.dockClickAction {
        case .system: return
        case .hide: app.hide()
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
        let windows = visibleWindows()
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
        quitWatch = QuitWatchState()
        if let counts = currentWindowCounts() { quitWatch.prime(counts) }
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
        quitWatch = QuitWatchState()
    }

    private func checkWindows() {
        // Without the Accessibility permission the windows cannot be counted, and a
        // count that is wrong in this direction quits apps that still have windows.
        // So nothing is quit at all until the permission is there.
        guard let current = currentWindowCounts() else { return }
        for pid in quitWatch.update(current) {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  bundleID != "com.apple.finder",
                  !settings.neverQuitApps.contains(bundleID) else { continue }
            app.terminate()
        }
    }

    /// How many windows each running app has, counted through the accessibility API so
    /// that minimized windows and windows on other Spaces count too. The window server's
    /// on-screen list has neither, which used to make Sonary quit apps whose windows were
    /// merely out of sight.
    ///
    /// Nil when Accessibility is not granted. An app that does not answer is left out
    /// rather than recorded as empty, so an unresponsive app is never quit for it.
    private func currentWindowCounts() -> [Int32: Int]? {
        guard AXIsProcessTrusted() else { return nil }
        var counts: [Int32: Int] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            // Every window counts, panels and dialogs included: counting one too many
            // only delays a quit, counting one too few ends an app that was still in use.
            counts[app.processIdentifier] = windows.count
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
        guard !frontAppKeepsItsLayout else { return }
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

    /// Every ordinary window on screen, with its frame in pointer coordinates.
    private func visibleWindows() -> [(pid: Int32, frame: CGRect)] {
        guard let primary = NSScreen.screens.first else { return [] }
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return ((raw as? [[String: Any]]) ?? []).compactMap { window in
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
    }

    /// The window an app has in front, for grabbing with a modifier-drag.
    private func frontWindow(of pid: Int32) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(focused, to: AXUIElement.self)
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
        // Key-ups and modifier changes too: holding has to notice when the keys are let go,
        // or the next press would count the old hold and quit at once.
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: quitTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            quitProtectionNeedsAccessibility = true
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        quitTap = tap
        quitSource = source
        quitProtectionNeedsAccessibility = false
    }

    private func removeQuitTap() {
        if let quitTap { CGEvent.tapEnable(tap: quitTap, enable: false) }
        if let quitSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), quitSource, .commonModes) }
        quitTap = nil
        quitSource = nil
        holdGuard.up()
        quitProtectionNeedsAccessibility = false
    }

    /// False swallows the key press.
    func shouldPass(type: CGEventType, flags: CGEventFlags, keyCode: Int64, isRepeat: Bool,
                    isSynthetic: Bool = false) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let quitTap { CGEvent.tapEnable(tap: quitTap, enable: true) }
            return true
        }
        // The plain ⌘Q Sonary sends after ⌥ confirmed it.
        if isSynthetic { return true }
        let confirmation = modifierConfirmation(command: flags.contains(.maskCommand),
                                                option: flags.contains(.maskAlternate),
                                                shift: flags.contains(.maskShift),
                                                control: flags.contains(.maskControl))
        // With ⌥ as the confirmation, ⌥⌘Q is the protected combination too; otherwise only ⌘Q.
        let combinationMatches = settings.quitConfirmation == .extraModifier
            ? confirmation != .pass
            : confirmation == .holdBack
        let key: ProtectedKey? = switch keyCode {
        case 12 where settings.quitProtection: .quit
        case 13 where settings.closeProtection: .close
        default: nil
        }
        guard type == .keyDown, combinationMatches, let key,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, bundleID != "com.apple.finder",
              isProtected(bundleID: bundleID, onlyApps: settings.protectedApps) else {
            // Anything but the protected keys still going down ends a hold: a key let go,
            // ⌘ released, another key pressed.
            if settings.quitConfirmation == .hold, holdGuard.isHolding {
                holdGuard.up()
                hideHUD()
            }
            return true
        }
        // Holding needs the repeats, which is how it knows the keys are still down. For the
        // other ways a repeat is held back like the first press: a held ⌘Q must not slip
        // through as its own repeats.
        if isRepeat && settings.quitConfirmation != .hold { return false }
        let now = ProcessInfo.processInfo.systemUptime
        switch settings.quitConfirmation {
        case .extraModifier:
            if confirmation == .sendPlain {
                sendPlainCommand(keyCode: keyCode)
                hideHUD()
            } else {
                showHUD(appName: app.localizedName ?? bundleID, key: key, withOption: true)
            }
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
    private func showHUD(appName: String, key: ProtectedKey, progress: Double? = nil, withOption: Bool = false) {
        let text = withOption ? optionHintText(appName: appName, key: key)
            : hudText(appName: appName, key: key, holding: progress != nil)
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

    private func optionHintText(appName: String, key: ProtectedKey) -> String {
        switch key {
        case .quit: String(localized: "Press ⌥⌘Q to quit \(appName)", bundle: .module)
        case .close: String(localized: "Press ⌥⌘W to close this window", bundle: .module)
        }
    }

    /// Sends ⌘Q or ⌘W on its own, marked so the tap lets it through, after ⌥ confirmed it.
    private func sendPlainCommand(keyCode: Int64) {
        Task { @MainActor in
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
                else { continue }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: quitTapSyntheticMarker)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    // MARK: Green button

    private func installGreenButtonTap() {
        guard greenButtonTap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: greenButtonTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        greenButtonTap = tap
        greenButtonSource = source
    }

    private func removeGreenButtonTap() {
        if let greenButtonTap { CGEvent.tapEnable(tap: greenButtonTap, enable: false) }
        if let greenButtonSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), greenButtonSource, .commonModes) }
        greenButtonTap = nil
        greenButtonSource = nil
        pendingGreenButtonWindow = nil
    }

    /// False swallows the click. A click on a window's green full-screen button becomes a
    /// maximize (or, on a window already filling the screen, a step back); ⌥-click and the
    /// apps on the exception list keep what macOS does.
    func greenButtonShouldPass(type: CGEventType, location: CGPoint, option: Bool) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let greenButtonTap { CGEvent.tapEnable(tap: greenButtonTap, enable: true) }
            pendingGreenButtonWindow = nil
            return true
        case .leftMouseDown:
            guard !option, let window = fullScreenButtonWindow(at: location) else { return true }
            pendingGreenButtonWindow = window
            return false
        case .leftMouseUp:
            guard let window = pendingGreenButtonWindow else { return true }
            pendingGreenButtonWindow = nil
            toggleMaximize(window)
            return false
        default:
            return true
        }
    }

    /// The window whose green full-screen button is at this point, if it is one and its
    /// app is not on the exception list.
    private func fullScreenButtonWindow(at location: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(location.x), Float(location.y),
                                               &hit) == .success, let hit else { return nil }
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXSubroleAttribute as CFString, &subrole) == .success,
              (subrole as? String) == kAXFullScreenButtonSubrole else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard !isExcluded(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                          in: settings.greenButtonExceptions) else { return nil }
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(windowRef, to: AXUIElement.self)
    }

    /// Fills the window's screen, or puts it back when it already fills it.
    private func toggleMaximize(_ window: AXUIElement) {
        guard let primary = NSScreen.screens.first, let currentAX = frame(of: window) else { return }
        let height = primary.frame.height
        let current = cocoaRect(fromAX: currentAX, primaryScreenHeight: height)
        let middle = CGPoint(x: current.midX, y: current.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(middle) }) ?? NSScreen.main else { return }
        let target = axRect(fromCocoa: layoutFrame(.maximize, visible: screen.visibleFrame, current: current),
                            primaryScreenHeight: height)
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        if framesMatch(currentAX, target), let saved = previousFrames[pid] {
            setFrame(saved, of: window)
            previousFrames[pid] = nil
        } else {
            previousFrames[pid] = currentAX
            setFrame(target, of: window)
        }
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
