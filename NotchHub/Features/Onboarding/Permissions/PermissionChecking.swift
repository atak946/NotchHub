import AppKit
import AVFoundation
import CoreServices
import EventKit
import OSLog
import UserNotifications

/// OS boundary for reading and requesting every `AppPermission`; faked in tests.
@MainActor
protocol PermissionChecking: AnyObject {
    /// Reads the current state without prompting.
    func status(of permission: AppPermission) async -> PermissionStatus
    /// Explicit user action: shows the system prompt where macOS still offers one.
    func request(_ permission: AppPermission) async
    func openSettings(for permission: AppPermission)
}

/// Live implementation backed by EventKit, AX, Apple Events, UserNotifications and AVFoundation.
@MainActor
final class SystemPermissionChecker: PermissionChecking {
    /// Players controlled over Apple Events; `KnownApps`-style constants kept local to this boundary.
    static let automationTargets = ["com.spotify.client", "com.apple.Music"]
    static let fallbackAutomationTarget = "com.apple.Music"
    static let cameraUsageKey = "NSCameraUsageDescription"
    /// Time for a freshly launched player to accept Apple Events before we ask.
    static let launchSettleDelay: Duration = .milliseconds(1500)

    private let accessibility: any AccessibilityTrustChecking
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Onboarding")

    init(accessibility: any AccessibilityTrustChecking = SystemAccessibilityTrust()) {
        self.accessibility = accessibility
    }

    func status(of permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .calendar:
            return PermissionStatusMapping.calendar(EKEventStore.authorizationStatus(for: .event))
        case .accessibility:
            return PermissionStatusMapping.accessibility(isTrusted: accessibility.isTrusted(prompt: false))
        case .automation:
            return await automationStatus()
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return PermissionStatusMapping.notifications(settings.authorizationStatus)
        case .camera:
            return PermissionStatusMapping.camera(AVCaptureDevice.authorizationStatus(for: .video))
        }
    }

    func request(_ permission: AppPermission) async {
        logger.info("Requesting permission \(permission.rawValue, privacy: .public)")
        switch permission {
        case .calendar: await requestCalendar()
        case .accessibility: _ = accessibility.isTrusted(prompt: true)
        case .automation: await requestAutomation()
        case .notifications: await requestNotifications()
        case .camera: await requestCamera()
        }
    }

    func openSettings(for permission: AppPermission) {
        guard let url = permission.settingsURL() else {
            logger.error("No settings pane for \(permission.rawValue, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Requests

    private func requestCalendar() async {
        let store = EKEventStore()
        do {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestFullAccessToEvents { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            logger.info("Calendar access granted: \(granted, privacy: .public)")
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            logger.info("Notification authorization granted: \(granted, privacy: .public)")
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestCamera() async {
        // Without a usage description macOS terminates the app on request, so refuse instead.
        guard Bundle.main.object(forInfoDictionaryKey: Self.cameraUsageKey) != nil else {
            logger.error("Camera request skipped: \(Self.cameraUsageKey, privacy: .public) missing from Info.plist")
            return
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        logger.info("Camera access granted: \(granted, privacy: .public)")
    }

    private func requestAutomation() async {
        var targets = runningAutomationTargets()
        if targets.isEmpty {
            // Apple Events consent can only be asked while the target runs; start Music hidden.
            await launchHidden(bundleID: Self.fallbackAutomationTarget)
            targets = [Self.fallbackAutomationTarget]
        }
        for target in targets {
            let code = await Self.determineAutomation(target: target, askUser: true)
            logger.info("Automation consent for \(target, privacy: .public): \(code, privacy: .public)")
        }
    }

    // MARK: - Automation helpers

    private func automationStatus() async -> PermissionStatus {
        var results: [PermissionStatus?] = []
        for target in Self.automationTargets {
            let code = await Self.determineAutomation(target: target, askUser: false)
            results.append(PermissionStatusMapping.automation(code))
        }
        return PermissionStatusMapping.combinedAutomation(results)
    }

    private func runningAutomationTargets() -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.automationTargets.filter { running.contains($0) }
    }

    private func launchHidden(bundleID: String) async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.error("Automation target \(bundleID, privacy: .public) is not installed")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            try await Task.sleep(for: Self.launchSettleDelay)
        } catch {
            logger.error("Launching \(bundleID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `AEDeterminePermissionToAutomateTarget` blocks while the consent dialog is up, so it runs off the main actor.
    nonisolated static func determineAutomation(target bundleID: String, askUser: Bool) async -> OSStatus {
        await Task.detached(priority: .userInitiated) {
            let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let address = descriptor.aeDesc else { return PermissionStatusMapping.automationTargetNotRunningCode }
            return AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, askUser)
        }.value
    }
}
