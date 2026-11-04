import AppKit
@preconcurrency import AVFoundation
import SwiftUI

/// A small mirror of the camera, for checking yourself before a call.
@MainActor
final class CameraPreviewController {
    private var panel: NSPanel?
    private var session: AVCaptureSession?

    var isShowing: Bool { panel != nil }

    func toggle() {
        if isShowing { close() } else { show() }
    }

    func show() {
        guard panel == nil else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        self.session = session

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
                            styleMask: [.borderless, .nonactivatingPanel, .resizable],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CameraPreviewView(session: session, close: { [weak self] in
            self?.close()
        }))
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - 360, y: screen.visibleFrame.minY + 40))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        Task.detached { session.startRunning() }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        if let session {
            Task.detached { session.stopRunning() }
        }
        session = nil
    }
}

private struct CameraLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

struct CameraPreviewView: View {
    let session: AVCaptureSession
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        CameraLayerView(session: session)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .shadow(radius: 10)
            .onHover { hovering = $0 }
    }
}
