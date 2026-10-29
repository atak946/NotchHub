import AppKit
import Carbon.HIToolbox
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    /// Created at launch so it remembers which language is running.
    let language = AppLanguageSettings()
    let alerts = NotchAlertCenter()
    private(set) lazy var services = ModuleServices(settings: settings, alerts: alerts)
    private let fullScreenDetector = FullScreenDetector()
    private(set) lazy var windowManager = NotchWindowManager(
        settings: settings,
        fullScreenDetector: fullScreenDetector,
        services: services,
        alerts: alerts
    )
    private lazy var alertRouter = AlertRouter(
        settings: settings,
        services: services,
        alerts: alerts
    ) { [weak self] module in
        self?.windowManager.present(module)
    }
    private var hotKey: GlobalHotKey?
    private lazy var statusMenu = StatusMenuController(
        settings: settings,
        windowManager: windowManager,
        updater: updater,
        micMute: services.system.micMute,
        supportActions: supportActions
    )
    private lazy var micMuteHotKey = MicMuteHotKey(controller: services.system.micMute)

    // MARK: Updates (Sparkle; inert unless the build defines a feed and key)
    private(set) lazy var updater: UpdaterService = {
        let updater = UpdaterService(alerts: alerts)
        updater.canPostAlert = { [settings] in settings.alertsEnabled && !settings.isPaused }
        return updater
    }()

    // MARK: Onboarding and diagnostics
    let permissions = PermissionsModel()
    private(set) lazy var onboarding = OnboardingWindowController(permissions: permissions)
    private(set) lazy var diagnostics = DiagnosticsReporter(settings: settings, permissions: permissions, alerts: alerts)
    private lazy var crashReports = CrashReportMonitor(alerts: alerts)
    var supportActions: SupportActions {
        SupportActions(
            openOnboarding: { [weak self] in self?.onboarding.show() },
            reportIssue: { [weak self] in
                guard let diagnostics = self?.diagnostics else { return }
                Task { await diagnostics.report() }
            }
        )
    }

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "App")

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests, !ScreenshotRenderer.runIfRequested() else { return }

        fullScreenDetector.start()
        services.start()
        alertRouter.start()
        windowManager.start()
        IntentServicesBridge.shared.configure(
            LiveIntentRoutes(services: services, settings: settings, alerts: alerts, panel: windowManager)
        )
        registerHotKey()
        micMuteHotKey.start()
        updater.start()
        statusMenu.install()
        permissions.onGranted = { [weak self] permission in
            if permission == .calendar { self?.services.calendar.refresh() }
        }
        onboarding.showIfNeeded()
        crashReports.checkOnLaunch()
        logger.info("NotchHub started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        crashReports.recordCleanExit()
        hotKey?.unregister()
        micMuteHotKey.stop()
        services.stop()
    }

    /// `notchhub://alert?...` and `notchhub://open?module=...` from scripts and the CLI.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where !services.externalAlerts.handle(url: url) {
            logger.error("Rejected external URL request")
        }
    }

    private func registerHotKey() {
        let hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak self] in
            self?.windowManager.togglePanel()
        }
        if !hotKey.register() {
            logger.error("Failed to register global hot key ⌥⌘N")
        }
        self.hotKey = hotKey
    }
}
