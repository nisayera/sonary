import AppKit
import SonaryCore
import SwiftUI

// Quit protection (⌘Q / ⌘W held back until confirmed) and the green button that maximizes,
// split out of WindowsModel.swift. Both are event taps that can swallow input.
extension WindowsModel {
    // MARK: Quit protection

    func installQuitTap() {
        guard quitTap == nil else { return }
        // Key-ups and modifier changes too: holding has to notice when the keys are let go,
        // or the next press would count the old hold and quit at once.
        let tap = EventTap(mask: EventTap.mask([.keyDown, .keyUp, .flagsChanged])) { [weak self] type, event in
            // Read the event on the tap's callback; only Sendable values cross into the main actor.
            let flags = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let isOurs = event.getIntegerValueField(.eventSourceUserData) == quitTapSyntheticMarker
            let pass = MainActor.assumeIsolated {
                self?.shouldPass(type: type, flags: flags, keyCode: keyCode, isRepeat: isRepeat,
                                 isSynthetic: isOurs) ?? true
            }
            return pass ? .pass : .swallow
        }
        guard tap.start() else {
            quitProtectionNeedsAccessibility = true
            return
        }
        quitTap = tap
        quitProtectionNeedsAccessibility = false
    }

    func removeQuitTap() {
        quitTap?.stop()
        quitTap = nil
        holdGuard.up()
        quitProtectionNeedsAccessibility = false
    }

    /// False swallows the key press.
    func shouldPass(type: CGEventType, flags: CGEventFlags, keyCode: Int64, isRepeat: Bool,
                    isSynthetic: Bool = false) -> Bool {
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

    func installGreenButtonTap() {
        guard greenButtonTap == nil else { return }
        let tap = EventTap(mask: EventTap.mask([.leftMouseDown, .leftMouseUp])) { [weak self] type, event in
            let location = event.location
            let option = event.flags.contains(.maskAlternate)
            let pass = MainActor.assumeIsolated {
                self?.greenButtonShouldPass(type: type, location: location, option: option) ?? true
            }
            return pass ? .pass : .swallow
        }
        // A button-down may have been missed while macOS had the tap switched off.
        tap.onReenable = { [weak self] in self?.pendingGreenButtonWindow = nil }
        guard tap.start() else { return }
        greenButtonTap = tap
    }

    func removeGreenButtonTap() {
        greenButtonTap?.stop()
        greenButtonTap = nil
        pendingGreenButtonWindow = nil
    }

    /// False swallows the click. A click on a window's green full-screen button becomes a
    /// maximize (or, on a window already filling the screen, a step back); ⌥-click and the
    /// apps on the exception list keep what macOS does.
    func greenButtonShouldPass(type: CGEventType, location: CGPoint, option: Bool) -> Bool {
        switch type {
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
