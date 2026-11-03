import AppKit
import SonaryUI
import SwiftUI

final class CleaningPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Blacks out every screen so the keyboard and the display can be wiped without
/// typing into anything. Escape or a click ends it; nothing is ever locked away.
@MainActor
final class CleaningModeController {
    private var panels: [CleaningPanel] = []

    var isActive: Bool { !panels.isEmpty }

    func start() {
        guard panels.isEmpty else { return }
        for screen in NSScreen.screens {
            let panel = CleaningPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .black
            panel.isOpaque = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: CleaningModeView(stop: { [weak self] in self?.stop() }))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSApp.activate()
        panels.first?.makeKey()
    }

    func stop() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
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
                    .font(.callout).foregroundStyle(.secondary)
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
