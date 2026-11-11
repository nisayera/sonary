import AppKit
import SonaryCore
import SonaryUI
import SwiftUI

final class CleaningPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The key the cleaning tap lets end it.
private let escapeKeyCode: Int64 = 53

/// What the cleaning tap does with an event: swallow it, or stop cleaning mode (Escape).
public enum CleaningKeyVerdict: Equatable, Sendable {
    case swallow, stop
}

/// Every key, including brightness, volume and media keys and the ones that open Mission
/// Control, is swallowed while cleaning; a plain Escape press ends it.
public func cleaningVerdict(isKeyDown: Bool, keyCode: Int64) -> CleaningKeyVerdict {
    isKeyDown && keyCode == escapeKeyCode ? .stop : .swallow
}

/// Blacks out every screen so the keyboard and the display can be wiped without
/// typing into anything. Escape ends it, and in the black version a click does too;
/// nothing is ever locked away.
@MainActor
final class CleaningModeController {
    private var panels: [CleaningPanel] = []
    /// Swallows every key; a plain Escape press ends cleaning mode.
    private lazy var tap = EventTap(mask: Self.tapMask) { [weak self] type, event in
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if cleaningVerdict(isKeyDown: type == .keyDown, keyCode: keyCode) == .stop {
            // Not from inside the tap's own callback, which stopping removes.
            Task { @MainActor [weak self] in self?.stop() }
        }
        return .swallow
    }
    /// Also swallow the system keys, which reach macOS before any window sees them.
    var blocksSystemKeys = true
    /// A small badge over a visible screen instead of black. Clicks are swallowed then
    /// rather than ending it, so a trackpad can be wiped too.
    var indicatorOnly = false

    var isActive: Bool { !panels.isEmpty }

    func start() {
        guard panels.isEmpty else { return }
        for screen in NSScreen.screens {
            let panel = CleaningPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            panel.level = .screenSaver
            // Nearly clear still catches clicks; fully clear windows let them through.
            panel.backgroundColor = indicatorOnly ? NSColor.black.withAlphaComponent(0.02) : .black
            panel.isOpaque = !indicatorOnly
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let stop: () -> Void = { [weak self] in self?.stop() }
            panel.contentView = indicatorOnly
                ? NSHostingView(rootView: AnyView(CleaningIndicatorView(stop: stop)))
                : NSHostingView(rootView: AnyView(CleaningModeView(stop: stop)))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        if blocksSystemKeys { installTap() }
        NSApp.activate()
        panels.first?.makeKey()
    }

    func stop() {
        removeTap()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }

    private static var tapMask: CGEventMask {
        let systemDefined = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
        return EventTap.mask([.keyDown, .keyUp, .flagsChanged]) | systemDefined
    }

    /// Without Accessibility there is no tap; the panels still take the ordinary keys.
    private func installTap() {
        tap.start(promptForAccessibility: false)
    }

    private func removeTap() {
        tap.stop()
    }
}

struct CleaningModeView: View {
    let stop: () -> Void
    @State private var visible = true

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(Color.sonaryAccent)
                Text("Keyboard and screen are locked for cleaning", bundle: .module)
                    .font(.title3.weight(.semibold))
                Text("Press Escape or click to stop", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .opacity(visible ? 1 : 0.25)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { stop() }
        .onExitCommand { stop() }
        .environment(\.colorScheme, .dark)
    }
}

/// The screen stays as it is, with a small badge in the middle saying how to get out.
struct CleaningIndicatorView: View {
    let stop: () -> Void

    var body: some View {
        ZStack {
            Color.clear
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.sonaryAccent)
                Text("Cleaning: keys and clicks are off. Press Escape to stop.", bundle: .module)
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        // Clicks land here and go no further.
        .onTapGesture {}
        .onExitCommand { stop() }
    }
}
