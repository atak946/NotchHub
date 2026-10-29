import AppKit
import Observation
import OSLog

/// Online/offline, interface type and Wi-Fi network, with debounced alerts.
@MainActor
@Observable
final class NetworkMonitor {
    /// A change must hold this long before it is committed, so flapping Wi-Fi does not spam.
    static let debounceInterval: TimeInterval = 3
    static let alertKey = "network.state"
    static let changedAlertDuration: Duration = .seconds(3)
    static let backOnlineAlertDuration: Duration = .seconds(4)

    private static let networkSettingsURL = "x-apple.systempreferences:com.apple.Network-Settings.extension"

    enum Keys {
        static let isEnabled = "Network.isEnabled"
        static let alertsEnabled = "Network.alertsEnabled"
        static let changeAlertsEnabled = "Network.changeAlertsEnabled"
    }

    /// Debounced snapshot; `nil` until the first path update.
    private(set) var snapshot: NetworkSnapshot?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            applyRunningState()
        }
    }

    /// Offline / back-online alerts.
    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    /// "Ağ değişti" alerts.
    var changeAlertsEnabled: Bool {
        didSet { defaults.set(changeAlertsEnabled, forKey: Keys.changeAlertsEnabled) }
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let reader: any NetworkPathReading
    @ObservationIgnored private let clock: any SystemClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let settleAction: SystemDelayedAction
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Network")
    @ObservationIgnored private var debouncer = SystemDebouncer<NetworkSnapshot>(holdInterval: NetworkMonitor.debounceInterval)
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var isMonitoring = false

    init(
        alerts: NotchAlertCenter,
        reader: any NetworkPathReading = SystemNetworkPathReader(),
        clock: any SystemClock = SystemLiveClock(),
        defaults: UserDefaults = .standard
    ) {
        self.alerts = alerts
        self.reader = reader
        self.clock = clock
        self.defaults = defaults
        settleAction = SystemDelayedAction(clock: clock)
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        changeAlertsEnabled = defaults.object(forKey: Keys.changeAlertsEnabled) as? Bool ?? true
    }

    var isOnline: Bool { snapshot?.isOnline ?? false }

    /// Offline glyph beside the notch.
    var hasCompactIndicator: Bool {
        isEnabled && snapshot?.isOnline == false
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

    /// Feeds one raw path reading into the debouncer.
    func handle(_ raw: NetworkSnapshot) {
        if let committed = debouncer.observe(raw, at: clock.now) {
            commit(committed)
        }
        scheduleSettleIfNeeded()
    }

    /// Commits a pending reading once it has been held for `debounceInterval`.
    func settle() {
        if let committed = debouncer.settle(at: clock.now) {
            commit(committed)
        }
        scheduleSettleIfNeeded()
    }

    func openNetworkSettings() {
        guard let url = URL(string: Self.networkSettingsURL), NSWorkspace.shared.open(url) else {
            logger.error("Could not open network settings")
            return
        }
    }

    // MARK: - Private

    private func scheduleSettleIfNeeded() {
        guard let settleDate = debouncer.settleDate else {
            settleAction.cancel()
            return
        }
        settleAction.schedule(after: settleDate.timeIntervalSince(clock.now)) { [weak self] in
            self?.settle()
        }
    }

    private func commit(_ new: NetworkSnapshot) {
        let old = snapshot
        snapshot = new
        guard let event = NetworkAlertPolicy.event(from: old, to: new) else { return }
        logger.info("Network event: \(String(describing: event), privacy: .private)")
        post(event)
    }

    private func post(_ event: NetworkEvent) {
        guard isEnabled else { return }
        switch event {
        case .wentOffline:
            guard alertsEnabled else { return }
            alerts.post(NotchAlert(
                module: .status,
                systemImage: "wifi.slash",
                title: "Çevrimdışısın",
                subtitle: "Ağ bağlantısı yok",
                style: .urgent,
                coalescingKey: Self.alertKey,
                autoDismissAfter: nil,
                actionTitle: "Ayarlar",
                action: { [weak self] in self?.openNetworkSettings() }
            ))
        case .backOnline(let snapshot):
            guard alertsEnabled else { return }
            alerts.post(NotchAlert(
                module: .status,
                systemImage: snapshot.interface.systemImage,
                title: "Tekrar çevrimiçi",
                subtitle: snapshot.displayName,
                style: .success,
                coalescingKey: Self.alertKey,
                autoDismissAfter: Self.backOnlineAlertDuration
            ))
        case .changed(let snapshot):
            guard changeAlertsEnabled else { return }
            alerts.post(NotchAlert(
                module: .status,
                systemImage: snapshot.interface.systemImage,
                title: "Ağ değişti",
                subtitle: "Şu an: \(snapshot.displayName)",
                style: .info,
                coalescingKey: Self.alertKey,
                autoDismissAfter: Self.changedAlertDuration
            ))
        }
    }

    private func applyRunningState() {
        let shouldMonitor = isStarted && isEnabled
        if shouldMonitor, !isMonitoring {
            isMonitoring = true
            reader.startObserving { [weak self] raw in self?.handle(raw) }
        } else if !shouldMonitor, isMonitoring {
            isMonitoring = false
            reader.stopObserving()
            settleAction.cancel()
            debouncer.reset()
            snapshot = nil
        }
    }
}
