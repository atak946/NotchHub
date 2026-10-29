import AppKit
import Observation
import OSLog

/// Watches the VPN tunnel (any known VPN client or utun/ipsec tunnel) and alerts when it drops.
@MainActor
@Observable
final class VPNMonitor {
    /// A state must hold this long before it is committed (≥ 5 s per spec).
    static let debounceInterval: TimeInterval = 5
    /// Backup poll in case a change notification is missed (SCDynamicStore and NWPathMonitor are primary).
    static let pollInterval: TimeInterval = 30
    static let alertKey = "vpn.state"
    static let reconnectedAlertDuration: Duration = .seconds(4)

    enum Keys {
        static let isEnabled = "VPN.isEnabled"
        static let alertsEnabled = "VPN.alertsEnabled"
    }

    /// Debounced state shown in the UI.
    private(set) var state: VPNState = .unknown
    private(set) var tunnelInterfaces: [String] = []
    /// Known client currently running, if any.
    private(set) var runningClient: VPNClient?
    /// Known clients found on disk; loaded when monitoring starts.
    private(set) var installedClients: [VPNInstalledClient] = []

    var isClientRunning: Bool { runningClient != nil }

    /// Name of the detected client (running first, then installed), or `nil` when none is known.
    var clientDisplayName: String? {
        runningClient?.displayName ?? installedClients.first?.displayName
    }

    /// Detected client name or the generic "VPN".
    var displayName: String { clientDisplayName ?? VPNClientCatalog.genericName }

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            applyRunningState()
        }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let runningApps: SystemRunningApps
    @ObservationIgnored private let reader: any VPNSystemReading
    @ObservationIgnored private let clock: any SystemClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loadInstalledClients: @MainActor () -> [VPNInstalledClient]
    @ObservationIgnored private let settleAction: SystemDelayedAction
    @ObservationIgnored private let poller: SystemPoller
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "VPN")
    @ObservationIgnored private var debouncer = SystemDebouncer<VPNState>(holdInterval: VPNMonitor.debounceInterval)
    @ObservationIgnored private var tracker = VPNTransitionTracker()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var isMonitoring = false

    init(
        alerts: NotchAlertCenter,
        runningApps: SystemRunningApps,
        reader: any VPNSystemReading = SystemVPNReader(),
        clock: any SystemClock = SystemLiveClock(),
        defaults: UserDefaults = .standard,
        installedClients: @escaping @MainActor () -> [VPNInstalledClient] = { VPNClientLocator.installedClients() }
    ) {
        self.alerts = alerts
        self.runningApps = runningApps
        self.reader = reader
        self.clock = clock
        self.defaults = defaults
        loadInstalledClients = installedClients
        settleAction = SystemDelayedAction(clock: clock)
        poller = SystemPoller(clock: clock)
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
    }

    /// Red shield beside the notch only while the VPN is down after having been up.
    var hasCompactIndicator: Bool {
        isEnabled && tracker.isDropped && state == .disconnected
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

    /// Reads the system once and feeds the debouncer.
    func refresh() {
        let sample = reader.sample()
        if sample.tunnelInterfaces != tunnelInterfaces {
            tunnelInterfaces = sample.tunnelInterfaces
        }
        let running = VPNClientLocator.runningClient(in: runningApps.apps, installed: installedClients)
        if running != runningClient {
            runningClient = running
        }
        observe(VPNClassifier.state(for: sample))
    }

    /// Commits a pending state once it has been held for `debounceInterval`.
    func settle() {
        if let committed = debouncer.settle(at: clock.now) {
            commit(committed)
        }
        scheduleSettleIfNeeded()
    }

    /// App to open: the running client if it is installed, else the first installed one.
    var launchTarget: VPNInstalledClient? {
        installedClients.first { $0.client == runningClient } ?? installedClients.first
    }

    func openClient() {
        guard let url = launchTarget?.appURL else {
            logger.info("No known VPN client app found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Private

    private func observe(_ classified: VPNState) {
        if let committed = debouncer.observe(classified, at: clock.now) {
            commit(committed)
        }
        scheduleSettleIfNeeded()
    }

    private func scheduleSettleIfNeeded() {
        guard let settleDate = debouncer.settleDate else {
            settleAction.cancel()
            return
        }
        settleAction.schedule(after: settleDate.timeIntervalSince(clock.now)) { [weak self] in
            self?.settle()
        }
    }

    private func commit(_ newState: VPNState) {
        if newState != state {
            logger.info("VPN state: \(newState.rawValue, privacy: .public)")
            state = newState
        }
        guard let event = tracker.handle(newState) else { return }
        post(event)
    }

    private func post(_ event: VPNEvent) {
        guard isEnabled, alertsEnabled else { return }
        let clientName = clientDisplayName
        switch event {
        case .dropped:
            let hasClient = launchTarget != nil
            var openAction: (@MainActor () -> Void)?
            if hasClient {
                openAction = { [weak self] in
                    self?.openClient()
                }
            }
            alerts.post(NotchAlert(
                module: .status,
                systemImage: "lock.slash.fill",
                title: "VPN bağlantısı koptu",
                subtitle: clientName,
                style: .urgent,
                coalescingKey: Self.alertKey,
                autoDismissAfter: NotchAlert.importantDuration,
                actionTitle: hasClient ? "Aç" : nil,
                action: openAction
            ))
        case .reconnected:
            alerts.post(NotchAlert(
                module: .status,
                systemImage: "lock.shield.fill",
                title: "VPN yeniden bağlandı",
                subtitle: clientName,
                style: .success,
                coalescingKey: Self.alertKey,
                autoDismissAfter: Self.reconnectedAlertDuration
            ))
        }
    }

    private func applyRunningState() {
        let shouldMonitor = isStarted && isEnabled
        if shouldMonitor, !isMonitoring {
            isMonitoring = true
            installedClients = loadInstalledClients()
            reader.startObserving { [weak self] in self?.refresh() }
            poller.start(every: Self.pollInterval) { [weak self] in self?.refresh() }
            trackRunningApps()
            refresh()
        } else if !shouldMonitor, isMonitoring {
            isMonitoring = false
            reader.stopObserving()
            poller.stop()
            settleAction.cancel()
            debouncer.reset()
            tracker = VPNTransitionTracker()
            state = .unknown
        }
    }

    private func trackRunningApps() {
        withObservationTracking {
            _ = runningApps.apps
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isMonitoring else { return }
                self.refresh()
                self.trackRunningApps()
            }
        }
    }
}
