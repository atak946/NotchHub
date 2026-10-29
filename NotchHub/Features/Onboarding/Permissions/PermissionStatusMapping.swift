import AVFoundation
import CoreServices
import EventKit
import UserNotifications

/// Pure translations from each framework's authorization enum to `PermissionStatus`.
enum PermissionStatusMapping {
    /// `errAEEventWouldRequireUserConsent`: Automation has not been asked yet.
    static let automationConsentRequiredCode: OSStatus = -1744
    /// `errAEEventNotPermitted`: the user switched Automation off.
    static let automationNotPermittedCode: OSStatus = -1743
    /// `procNotFound`: the target app is not running, so the state is unknown.
    static let automationTargetNotRunningCode: OSStatus = -600

    static func calendar(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    static func notifications(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .provisional, .ephemeral: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        @unknown default: .denied
        }
    }

    static func camera(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    static func accessibility(isTrusted: Bool) -> PermissionStatus {
        isTrusted ? .granted : .notDetermined
    }

    /// `nil` when the target app is not running (or the result is unexpected) and tells us nothing.
    static func automation(_ code: OSStatus) -> PermissionStatus? {
        switch code {
        case noErr: .granted
        case automationConsentRequiredCode: .notDetermined
        case automationNotPermittedCode: .denied
        default: nil
        }
    }

    /// Automation is per target app: any grant counts, then any denial, otherwise not asked yet.
    static func combinedAutomation(_ statuses: [PermissionStatus?]) -> PermissionStatus {
        let known = statuses.compactMap { $0 }
        if known.contains(.granted) { return .granted }
        if known.contains(.denied) { return .denied }
        return .notDetermined
    }

    /// Apple Events consent can only be read while a player runs. When none does, fall back to the last
    /// state seen while one was running instead of reporting "not asked" after the user granted it.
    static func resolvedAutomation(_ statuses: [PermissionStatus?], lastKnown: PermissionStatus?) -> PermissionStatus {
        guard statuses.contains(where: { $0 != nil }) else { return lastKnown ?? .notDetermined }
        return combinedAutomation(statuses)
    }

    /// What the UI shows: an Accessibility request that did not lead to trust is treated as a denial,
    /// so the row offers "Ayarları aç" instead of a prompt that macOS no longer shows.
    static func displayed(
        _ raw: PermissionStatus,
        for permission: AppPermission,
        wasRequested: Bool
    ) -> PermissionStatus {
        guard permission.reportsDenialAsNotDetermined, wasRequested, raw == .notDetermined else { return raw }
        return .denied
    }
}
