import AppKit
import SwiftUI

/// A screenshot kept on top of everything, to compare or copy from while working elsewhere.
@MainActor
final class PinnedImageController {
    private var panels: [NSPanel] = []

    func pin(_ image: NSImage) {
        let scale = min(1, 420 / max(image.size.width, 1))
        let size = NSSize(width: max(image.size.width * scale, 120), height: max(image.size.height * scale, 90))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel, .resizable],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PinnedImageView(image: image, close: { [weak panel, weak self] in
            panel?.orderOut(nil)
            if let panel { self?.panels.removeAll { $0 === panel } }
        }))
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - size.width - 40,
                                         y: screen.visibleFrame.maxY - size.height - 40))
        }
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    func closeAll() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }
}

struct PinnedImageView: View {
    let image: NSImage
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel(Text("Close", bundle: .module))
                }
            }
            .shadow(radius: 12)
            .onHover { hovering = $0 }
            .onDrag { NSItemProvider(object: image) }
    }
}
