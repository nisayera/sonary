import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the island in a borderless panel at the top centre of the screen with the notch
/// (or of the main screen, where it is simulated) and keeps it there when screens change.
@MainActor
final class NotchWindowController {
    private let model: NotchModel
    private var panel: NotchPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var clickMonitor: Any?
    private var screenFrame: CGRect = .zero
    private var shrinkTask: Task<Void, Never>?

    init(model: NotchModel) {
        self.model = model
    }

    func show() {
        guard panel == nil else { return }
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        let host = NSHostingView(rootView: NotchView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel

        model.presentationChanged = { [weak self] presentation in self?.resize(for: presentation) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeOnScreen() }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.clickedOutside() }
        }
        placeOnScreen()
    }

    func close() {
        shrinkTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        screenObserver = nil
        clickMonitor = nil
        model.presentationChanged = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func placeOnScreen() {
        guard let panel else { return }
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? (model.settings.showOnScreensWithoutNotch ? NSScreen.main : nil) else {
            panel.orderOut(nil)
            return
        }
        screenFrame = screen.frame
        model.setNotchSize(NotchGeometry.notchSize(
            screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: NSStatusBar.system.thickness))
        resize(for: model.presentation)
        panel.orderFrontRegardless()
    }

    /// Grows at once when opening; shrinks after the closing animation so the content is not clipped.
    private func resize(for presentation: NotchPresentation) {
        guard let panel else { return }
        shrinkTask?.cancel()
        switch presentation {
        case .expanded:
            panel.setFrame(NotchGeometry.panelFrame(size: NotchModel.expandedSize, screenFrame: screenFrame), display: true)
        case .collapsed:
            let frame = NotchGeometry.panelFrame(size: model.notchSize, screenFrame: screenFrame)
            shrinkTask = Task { [weak panel] in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                panel?.setFrame(frame, display: true)
            }
        }
    }
}
