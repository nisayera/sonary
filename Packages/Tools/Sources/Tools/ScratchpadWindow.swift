import AppKit
import SwiftUI

/// The scratchpad in a window of its own that floats above the others, so a note stays in
/// view while you work in another app. It keeps its size and place between openings.
@MainActor
final class ScratchpadWindowController: NSObject, NSWindowDelegate {
    private var window: NSPanel?

    func show(model: ToolsModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
                             styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
                             backing: .buffered, defer: false)
        window.title = String(localized: "Scratchpad", bundle: .module)
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = CGSize(width: 300, height: 240)
        window.contentView = NSHostingView(rootView: ScratchpadEditor(model: model, editorHeight: nil)
            .padding(EdgeInsets(top: 30, leading: 12, bottom: 12, trailing: 12)))
        window.delegate = self
        if !window.setFrameUsingName("SonaryScratchpad") { window.center() }
        window.setFrameAutosaveName("SonaryScratchpad")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
