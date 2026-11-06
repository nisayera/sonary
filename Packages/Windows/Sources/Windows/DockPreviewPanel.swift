import AppKit
import ScreenCaptureKit
import SonaryUI
import SwiftUI

/// What can be done to a window from its Dock preview without bringing it forward.
enum DockWindowAction: Sendable {
    case close
    case minimize
}

/// The previews that appear when the pointer rests on a Dock icon: every window of
/// that app, including the ones on other Spaces, which is what the Dock itself will
/// not show you.
@MainActor
final class DockPreviewController {
    private var panel: NSPanel?

    func show(app: NSRunningApplication, windows: [DockWindow], near point: CGPoint,
              choose: @escaping (DockWindow) -> Void,
              act: @escaping (DockWindow, DockWindowAction) -> Void) {
        guard !windows.isEmpty else { return close() }
        let view = DockPreviewView(name: app.localizedName ?? "", windows: windows) { [weak self] window in
            self?.close()
            choose(window)
        } act: { [weak self] window, action in
            act(window, action)
            // The window is gone from the list either way; show the rest, or nothing.
            let rest = windows.filter { $0.id != window.id }
            self?.show(app: app, windows: rest, near: point, choose: choose, act: act)
        }
        let hosting = NSHostingView(rootView: view)
        let width = min(CGFloat(windows.count) * 150 + 24, 700)
        let size = CGSize(width: width, height: 150)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let origin = CGPoint(x: point.x - size.width / 2,
                             y: (screen?.visibleFrame.minY ?? point.y) + 12)
        panel.setFrame(CGRect(origin: clampToScreen(origin, size: size, screen: screen), size: size),
                       display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func clampToScreen(_ origin: CGPoint, size: CGSize, screen: NSScreen?) -> CGPoint {
        guard let frame = screen?.visibleFrame else { return origin }
        return CGPoint(x: min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8),
                       y: min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

private struct DockPreviewView: View {
    let name: String
    let windows: [DockWindow]
    let choose: (DockWindow) -> Void
    let act: (DockWindow, DockWindowAction) -> Void
    @State private var hovered: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: name).font(.caption.weight(.semibold)).padding(.horizontal, 4)
            HStack(spacing: 10) {
                ForEach(windows) { window in
                    Button { choose(window) } label: {
                        VStack(spacing: 4) {
                            WindowThumbnail(id: window.id)
                            Text(verbatim: window.title.isEmpty ? name : window.title)
                                .font(.caption2).lineLimit(1).frame(width: 130)
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        if hovered == window.id {
                            HStack(spacing: 4) {
                                windowButton("minus", label: Text("Minimize", bundle: .module)) { act(window, .minimize) }
                                windowButton("xmark", label: Text("Close", bundle: .module)) { act(window, .close) }
                            }
                            .padding(4)
                        }
                    }
                    .onHover { inside in hovered = inside ? window.id : (hovered == window.id ? nil : hovered) }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func windowButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// One window's picture, fetched once it arrives so the row never waits on the capture.
private struct WindowThumbnail: View {
    let id: UInt32
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
            }
        }
        .frame(width: 130, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: id) { image = await WindowPreviews.image(for: id) }
    }
}
