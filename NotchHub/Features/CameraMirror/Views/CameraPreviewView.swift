@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// Live, mirrored camera preview backed by `AVCaptureVideoPreviewLayer`.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}
}

final class CameraPreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        wantsLayer = true
        layer = previewLayer
        // The connection only exists once the session has its input; mirror it as soon as it runs.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidStartRunning(_:)),
            name: AVCaptureSession.didStartRunningNotification,
            object: session
        )
        applyMirroring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc nonisolated private func sessionDidStartRunning(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.applyMirroring() }
    }

    private func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
