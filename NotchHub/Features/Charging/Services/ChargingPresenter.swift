import Foundation
import Observation
import OSLog

/// Charging / unplug / full / low-battery presentations in the notch, shown through `NotchAlertCenter`.
/// IOKit changes are settled for a moment first, so an adapter that reports several states while
/// connecting (or a flapping cable) produces at most one presentation.
@MainActor
@Observable
final class ChargingPresenter {
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias Now = @Sendable () -> Date

    enum Keys {
        static let showsCharging = "charging.animationEnabled"
        static let warnsLowBattery = "charging.lowBatteryWarningEnabled"
    }

    /// IOKit sends several updates while an adapter negotiates; the last one within this window wins.
    static let settleDelay: Duration = .milliseconds(1500)
    static let alertKey = "power.charging"

    /// "Şarj animasyonu" (default on).
    var showsCharging: Bool {
        didSet {
            guard showsCharging != oldValue else { return }
            defaults.set(showsCharging, forKey: Keys.showsCharging)
            applyRunningState()
        }
    }

    /// "Düşük pil uyarısı" (default on).
    var warnsLowBattery: Bool {
        didSet {
            guard warnsLowBattery != oldValue else { return }
            defaults.set(warnsLowBattery, forKey: Keys.warnsLowBattery)
            applyRunningState()
        }
    }

    /// `false` on desktops; known once monitoring has read the power sources.
    private(set) var hasBattery = false

    /// Set by the integrator: `false` while notch alerts are off or NotchHub is paused.
    @ObservationIgnored var canPostAlert: @MainActor () -> Bool = { true }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let source: any PowerSourceMonitoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let now: Now
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Charging")
    @ObservationIgnored private var state = ChargingPolicyState.initial
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var isMonitoring = false
    /// The in-flight settle; exposed so tests can await it.
    @ObservationIgnored private(set) var pendingEvaluation: Task<Void, Never>?

    init(
        alerts: NotchAlertCenter,
        source: any PowerSourceMonitoring = IOKitPowerSourceMonitor(),
        defaults: UserDefaults = .standard,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        now: @escaping Now = { Date() }
    ) {
        self.alerts = alerts
        self.source = source
        self.defaults = defaults
        self.sleep = sleep
        self.now = now
        showsCharging = defaults.object(forKey: Keys.showsCharging) as? Bool ?? true
        warnsLowBattery = defaults.object(forKey: Keys.warnsLowBattery) as? Bool ?? true
    }

    private var preferences: ChargingPreferences {
        ChargingPreferences(showsCharging: showsCharging, warnsLowBattery: warnsLowBattery)
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

    /// An IOKit power change; evaluated once the readings have settled.
    func handleChange() {
        guard isMonitoring else { return }
        pendingEvaluation?.cancel()
        let sleep = self.sleep
        pendingEvaluation = Task { [weak self] in
            do {
                try await sleep(Self.settleDelay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingEvaluation = nil
            self.evaluate()
        }
    }

    // MARK: - Private

    private func applyRunningState() {
        let shouldMonitor = isStarted && (showsCharging || warnsLowBattery)
        if shouldMonitor, !isMonitoring {
            isMonitoring = true
            state = .initial
            // Baseline: the state at launch (or when re-enabled) is never presented.
            evaluate()
            source.startObserving { [weak self] in self?.handleChange() }
        } else if !shouldMonitor, isMonitoring {
            isMonitoring = false
            source.stopObserving()
            pendingEvaluation?.cancel()
            pendingEvaluation = nil
            state = .initial
        }
    }

    private func evaluate() {
        guard isMonitoring else { return }
        let snapshot = source.snapshot()
        hasBattery = snapshot != nil
        let decision = ChargingPolicy.evaluate(snapshot, state: state, now: now(), preferences: preferences)
        state = decision.state
        guard let event = decision.event else { return }
        present(event)
    }

    private func present(_ event: ChargingEvent) {
        guard canPostAlert() else { return }
        // Plug/unplug presentations are momentary: never queued behind (or interrupting) another alert.
        if !event.kind.isWarning, let current = alerts.current, current.coalescingKey != Self.alertKey { return }
        let content = ChargingAlertContent(event: event)
        alerts.post(NotchAlert(
            module: nil,
            systemImage: content.glyph.systemImage,
            title: content.title,
            subtitle: content.subtitle,
            style: content.style,
            coalescingKey: Self.alertKey,
            autoDismissAfter: content.duration,
            appName: String(localized: "Pil"),
            battery: content.glyph
        ))
        logger.info("Posted power presentation")
    }
}
