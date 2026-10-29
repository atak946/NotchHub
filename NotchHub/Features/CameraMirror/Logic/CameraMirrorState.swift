import Foundation

/// Camera permission, reduced to what the mirror needs.
enum CameraAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    /// Denied or restricted.
    case denied
}

/// The mirror's lifecycle. The camera runs only in `.live`, which is reachable only from an explicit `open`.
enum CameraMirrorState: Equatable, Sendable {
    case closed
    case requestingAccess
    case live
    case denied
    /// No camera, or the capture session could not be set up.
    case unavailable

    enum Event: Equatable, Sendable {
        /// The user clicked "Ayna" / "Kamerayı kontrol et".
        case open(CameraAuthorization)
        case accessResolved(granted: Bool)
        case captureFailed
        case close
        case timedOut
    }

    var isPresented: Bool { self != .closed }
    var isCameraRunning: Bool { self == .live }

    func reduce(_ event: Event) -> CameraMirrorState {
        switch event {
        case .open(let authorization):
            if self == .live || self == .requestingAccess { return self }
            switch authorization {
            case .notDetermined: return .requestingAccess
            case .authorized: return .live
            case .denied: return .denied
            }
        case .accessResolved(let granted):
            // Closed (or anything else) while the prompt was up: the camera must not start afterwards.
            guard self == .requestingAccess else { return self }
            return granted ? .live : .denied
        case .captureFailed:
            return self == .live ? .unavailable : self
        case .close, .timedOut:
            return .closed
        }
    }
}
