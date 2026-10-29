@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Starts and stops the camera; `previewSession` feeds the preview layer.
protocol CameraCapturing: AnyObject, Sendable {
    var previewSession: AVCaptureSession? { get }
    /// `onFailure` runs on the main actor when there is no camera or the session cannot be configured.
    func start(onFailure: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

protocol CameraAuthorizing: Sendable {
    var status: CameraAuthorization { get }
    func requestAccess() async -> Bool
}

/// Live AVFoundation permission state.
struct AVCameraAuthorizer: CameraAuthorizing {
    private static let usageDescriptionKey = "NSCameraUsageDescription"

    var status: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        // Without the usage description TCC terminates the app on request; fail closed instead.
        guard Bundle.main.object(forInfoDictionaryKey: Self.usageDescriptionKey) != nil else {
            Logger(subsystem: AppIdentity.logSubsystem, category: "CameraMirror")
                .error("NSCameraUsageDescription missing; not requesting camera access")
            return false
        }
        return await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// One capture session with the default video device; all session work runs on a private serial queue.
final class AVCameraCapture: CameraCapturing, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "\(AppIdentity.logSubsystem).camera-mirror")
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CameraMirror")
    /// Only touched on `queue`.
    private var isConfigured = false

    var previewSession: AVCaptureSession? { session }

    func start(onFailure: @escaping @MainActor @Sendable () -> Void) {
        queue.async { [self] in
            guard configureIfNeeded() else {
                Task { @MainActor in onFailure() }
                return
            }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        guard let device = AVCaptureDevice.default(for: .video) else {
            logger.error("No video capture device")
            return false
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            guard session.canAddInput(input) else {
                logger.error("Capture session rejected the camera input")
                return false
            }
            session.addInput(input)
            isConfigured = true
            return true
        } catch {
            logger.error("Camera input failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
