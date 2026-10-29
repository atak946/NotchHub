import AppKit
import Observation
import OSLog
import Sparkle

/// Owns Sparkle's standard updater. Stays inert (`isAvailable == false`) unless the build has a feed and key.
@MainActor
@Observable
final class UpdaterService: NSObject {
    let currentVersion = AppVersion.current
    private(set) var isAvailable = false

    var automaticallyChecksForUpdates = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    var automaticallyDownloadsUpdates = false {
        didSet { controller?.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }

    /// Whether a notch alert may be posted right now (alerts enabled, not paused).
    @ObservationIgnored var canPostAlert: () -> Bool = { true }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let configuration: UpdaterConfiguration
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Updates")

    init(alerts: NotchAlertCenter, configuration: UpdaterConfiguration = .current) {
        self.alerts = alerts
        self.configuration = configuration
        super.init()
    }

    func start() {
        guard controller == nil else { return }
        guard configuration.isConfigured else {
            logger.info("Updates disabled: no feed URL or public key in this build")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller
        isAvailable = true
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
    }

    /// Brings Sparkle's UI to the front; also re-shows an update already found in the background.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    private func postReminder(for update: SUAppcastItem) {
        alerts.post(UpdateReminderAlert.make(version: update.displayVersionString) { [weak self] in
            self?.checkForUpdates()
        })
    }

    private func dismissReminder() {
        guard alerts.current?.coalescingKey == UpdateReminderAlert.coalescingKey else { return }
        alerts.dismiss()
    }
}

// Sparkle calls its user driver delegate on the main thread.
extension UpdaterService: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows the window itself only when it would be in utmost focus; otherwise the notch reminds.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus || !canPostAlert()
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            // LSUIElement app: without activation Sparkle's window opens behind other apps.
            NSApp.activate()
        } else {
            postReminder(for: update)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        dismissReminder()
    }

    func standardUserDriverWillFinishUpdateSession() {
        dismissReminder()
    }
}
