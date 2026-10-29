import AppKit
import AVFoundation
import Observation
import OSLog

/// The camera mirror hanging from the notch. Opens only on an explicit click, closes itself after a minute,
/// and stops the camera the moment it leaves `.live`.
@MainActor
@Observable
final class CameraMirrorService {
    static let autoCloseAfter: Duration = .seconds(60)
    private static let privacySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"

    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private(set) var state: CameraMirrorState = .closed
    /// The display whose notch shows the mirror while presented.
    private(set) var displayID: CGDirectDisplayID?

    /// Set by the window manager: the display under the mouse (or any visible notch); `nil` means no notch is shown.
    @ObservationIgnored var displayResolver: @MainActor () -> CGDirectDisplayID? = { nil }

    @ObservationIgnored private let capture: any CameraCapturing
    @ObservationIgnored private let authorizer: any CameraAuthorizing
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CameraMirror")

    init(
        capture: any CameraCapturing = AVCameraCapture(),
        authorizer: any CameraAuthorizing = AVCameraAuthorizer(),
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.capture = capture
        self.authorizer = authorizer
        self.sleep = sleep
    }

    var isPresented: Bool { state.isPresented }

    var previewSession: AVCaptureSession? { capture.previewSession }

    func isShown(on displayID: CGDirectDisplayID) -> Bool {
        state.isPresented && self.displayID == displayID
    }

    /// Explicit user action only. Requests permission when it has never been asked.
    func open() {
        guard let target = displayID ?? displayResolver() else {
            logger.notice("Camera mirror requested with no visible notch")
            return
        }
        displayID = target
        let authorization = authorizer.status
        apply(.open(authorization))
        scheduleAutoClose()
        if state == .requestingAccess {
            requestAccess()
        }
    }

    func close() {
        apply(.close)
    }

    func openPrivacySettings() {
        guard let url = URL(string: Self.privacySettingsURL), NSWorkspace.shared.open(url) else {
            logger.error("Could not open camera privacy settings")
            return
        }
        close()
    }

    // MARK: - Private

    private func apply(_ event: CameraMirrorState.Event) {
        let previous = state
        let next = previous.reduce(event)
        guard next != previous else { return }
        state = next
        if next.isCameraRunning, !previous.isCameraRunning {
            capture.start { [weak self] in self?.apply(.captureFailed) }
        } else if previous.isCameraRunning, !next.isCameraRunning {
            capture.stop()
        }
        if !next.isPresented {
            closeTask?.cancel()
            closeTask = nil
            displayID = nil
        }
    }

    private func requestAccess() {
        let authorizer = self.authorizer
        Task { [weak self] in
            let granted = await authorizer.requestAccess()
            self?.apply(.accessResolved(granted: granted))
        }
    }

    private func scheduleAutoClose() {
        closeTask?.cancel()
        let sleep = self.sleep
        closeTask = Task { [weak self] in
            do {
                try await sleep(Self.autoCloseAfter)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.apply(.timedOut)
        }
    }
}
