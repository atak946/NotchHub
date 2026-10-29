import AppKit
import Observation
import OSLog

/// Tracks whether any process uses the microphone or camera and warns about a forgotten open microphone.
@MainActor
@Observable
final class MicCameraMonitor {
    static let idleAlertMinuteOptions = [5, 10, 15, 30, 60]
    static let defaultIdleAlertMinutes = 10
    /// Backup poll in case a HAL listener is missed; waking from sleep also re-reads at once (SystemPoller).
    static let pollInterval: TimeInterval = 30
    static let idleAlertKey = "micCamera.idle"

    private static let secondsPerMinute: TimeInterval = 60
    private static let privacySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

    enum Keys {
        static let isEnabled = "MicCamera.isEnabled"
        static let alertsEnabled = "MicCamera.alertsEnabled"
        static let idleAlertMinutes = "MicCamera.idleAlertMinutes"
    }

    private(set) var snapshot: CaptureSnapshot = .idle
    private(set) var microphoneActiveSince: Date?

    /// Shows the indicator / tile state and posts alerts.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            applyRunningState()
        }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    var idleAlertMinutes: Int {
        didSet { defaults.set(idleAlertMinutes, forKey: Keys.idleAlertMinutes) }
    }

    /// Keeps the HAL listeners alive while meeting mode needs microphone state, even if `isEnabled` is off.
    var keepsMonitoringForMeetings = false {
        didSet { applyRunningState() }
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let runningApps: SystemRunningApps
    @ObservationIgnored private let reader: any CaptureDeviceReading
    @ObservationIgnored private let clock: any SystemClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let poller: SystemPoller
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MicCamera")
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var isMonitoring = false
    @ObservationIgnored private var didAlertThisSession = false

    init(
        alerts: NotchAlertCenter,
        runningApps: SystemRunningApps,
        reader: any CaptureDeviceReading = SystemCaptureDeviceReader(),
        clock: any SystemClock = SystemLiveClock(),
        defaults: UserDefaults = .standard
    ) {
        self.alerts = alerts
        self.runningApps = runningApps
        self.reader = reader
        self.clock = clock
        self.defaults = defaults
        poller = SystemPoller(clock: clock)
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        let storedMinutes = defaults.object(forKey: Keys.idleAlertMinutes) as? Int
        idleAlertMinutes = storedMinutes.flatMap { Self.idleAlertMinuteOptions.contains($0) ? $0 : nil }
            ?? Self.defaultIdleAlertMinutes
    }

    var isMicrophoneInUse: Bool { snapshot.isMicrophoneInUse }
    var isCameraInUse: Bool { snapshot.isCameraInUse }

    var hasCompactIndicator: Bool {
        isEnabled && (isMicrophoneInUse || isCameraInUse)
    }

    var runningMeetingApps: [MeetingApp] {
        MeetingAppCatalog.running(in: runningApps.apps)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        applyRunningState()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        applyRunningState()
    }

    /// Re-reads the HAL state and evaluates the idle-microphone alert.
    func refresh() {
        apply(reader.snapshot())
    }

    func openPrivacySettings() {
        guard let url = URL(string: Self.privacySettingsURL), NSWorkspace.shared.open(url) else {
            logger.error("Could not open microphone privacy settings")
            return
        }
    }

    // MARK: - State

    func apply(_ newSnapshot: CaptureSnapshot) {
        let wasMicOn = snapshot.isMicrophoneInUse
        if newSnapshot != snapshot {
            snapshot = newSnapshot
        }
        if newSnapshot.isMicrophoneInUse, !wasMicOn {
            microphoneActiveSince = clock.now
            didAlertThisSession = false
            logger.info("Microphone in use")
        } else if !newSnapshot.isMicrophoneInUse, wasMicOn {
            microphoneActiveSince = nil
            didAlertThisSession = false
            logger.info("Microphone released")
        }
        evaluateIdleAlert()
    }

    func evaluateIdleAlert() {
        let shouldAlert = MicIdlePolicy.shouldAlert(
            activeSince: microphoneActiveSince,
            now: clock.now,
            threshold: TimeInterval(idleAlertMinutes) * Self.secondsPerMinute,
            isMeetingAppRunning: !runningMeetingApps.isEmpty,
            alreadyAlerted: didAlertThisSession
        )
        guard shouldAlert, isEnabled, alertsEnabled else { return }
        didAlertThisSession = true
        let minutes = idleAlertMinutes
        alerts.post(NotchAlert(
            module: .status,
            systemImage: "mic.fill",
            title: "Mikrofon hâlâ kullanımda",
            subtitle: "Toplantı uygulaması açık değilken \(minutes) dk'dır açık",
            style: .info,
            coalescingKey: Self.idleAlertKey,
            actionTitle: "Ayarlar",
            action: { [weak self] in self?.openPrivacySettings() }
        ))
    }

    private func applyRunningState() {
        let shouldMonitor = isStarted && (isEnabled || keepsMonitoringForMeetings)
        if shouldMonitor, !isMonitoring {
            isMonitoring = true
            reader.startObserving { [weak self] in self?.refresh() }
            poller.start(every: Self.pollInterval) { [weak self] in self?.refresh() }
            refresh()
        } else if !shouldMonitor, isMonitoring {
            isMonitoring = false
            reader.stopObserving()
            poller.stop()
            apply(.idle)
        }
    }
}
