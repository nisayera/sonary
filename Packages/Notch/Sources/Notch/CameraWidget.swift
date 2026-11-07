@preconcurrency import AVFoundation
import SwiftUI

/// The notch's camera: a live picture from the front camera, for checking yourself
/// before a call without opening another app.
@MainActor
@Observable
public final class NotchCamera {
    @ObservationIgnored private(set) var session: AVCaptureSession?
    private(set) var isDenied = false

    public init() {}

    func start() {
        guard session == nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: open()
        case .notDetermined:
            // The answer comes on a background thread.
            AVCaptureDevice.requestAccess(for: .video) { @Sendable granted in
                Task { @MainActor [weak self] in
                    if granted { self?.open() } else { self?.isDenied = true }
                }
            }
        default: isDenied = true
        }
    }

    private func open() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            isDenied = true
            return
        }
        session.addInput(input)
        self.session = session
        Task.detached { session.startRunning() }
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        Task.detached { session.stopRunning() }
    }
}

struct NotchCameraView: View {
    let camera: NotchCamera

    var body: some View {
        Group {
            if camera.isDenied {
                EmptyWidget(symbol: "video.slash",
                            text: "Allow Sonary to use the camera in System Settings > Privacy & Security.")
            } else if let session = camera.session {
                CameraLayer(session: session)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { camera.start() }
        .onDisappear { camera.stop() }
    }
}

private struct CameraLayer: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(preview)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.sublayers?.first?.frame = view.bounds
    }
}
