import Foundation
import Observation
import OSLog

/// Reminds the user to get back to work when a distracting app comes to the front during a Pomodoro focus phase.
@MainActor
@Observable
final class FocusGuardService {
    static let alertKey = "focusGuard.reminder"
    static let alertDuration: Duration = .seconds(10)
    static let alertSymbol = "brain.head.profile"

    private enum Keys {
        static let isEnabled = "FocusGuard.isEnabled"
        static let apps = "FocusGuard.apps"
        static let cooldown = "FocusGuard.cooldownSeconds"
        static let log = "FocusGuard.distractionLog"
    }

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            applyObservation()
        }
    }

    /// Editable distraction list (persisted as JSON).
    var apps: [FocusApp] {
        didSet { defaults.set(FocusAppList.encode(apps), forKey: Keys.apps) }
    }

    var cooldown: TimeInterval {
        didSet { defaults.set(cooldown, forKey: Keys.cooldown) }
    }

    private(set) var isRunning = false
    private(set) var isObserving = false
    private(set) var lastDistraction: FocusActivation?
    private var log: FocusDistractionLog {
        didSet { defaults.set(try? JSONEncoder().encode(log), forKey: Keys.log) }
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let workspace: any FocusWorkspace
    @ObservationIgnored private let timerSnapshot: @MainActor () -> FocusTimerSnapshot
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let ownBundleID: String?
    @ObservationIgnored private let gracePeriod: TimeInterval
    @ObservationIgnored private var lastReminders: [String: Date] = [:]
    @ObservationIgnored private var lastFocusedApp: FocusActivation?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "FocusGuard")

    init(
        alerts: NotchAlertCenter,
        timerSnapshot: @escaping @MainActor () -> FocusTimerSnapshot,
        workspace: any FocusWorkspace,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current,
        ownBundleID: String? = Bundle.main.bundleIdentifier,
        gracePeriod: TimeInterval = FocusGuardPolicy.defaultGracePeriod
    ) {
        self.alerts = alerts
        self.timerSnapshot = timerSnapshot
        self.workspace = workspace
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.ownBundleID = ownBundleID?.lowercased()
        self.gracePeriod = gracePeriod
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        apps = FocusAppList.decode(defaults.data(forKey: Keys.apps)) ?? FocusApp.defaults
        cooldown = defaults.object(forKey: Keys.cooldown) as? TimeInterval ?? FocusGuardPolicy.defaultCooldown
        log = defaults.data(forKey: Keys.log).flatMap { try? JSONDecoder().decode(FocusDistractionLog.self, from: $0) }
            ?? FocusDistractionLog.empty(on: now(), calendar: calendar)
    }

    // MARK: - Derived state

    var distractionsToday: Int { log.count(on: now(), calendar: calendar) }

    /// `true` while a focus phase is running and the guard is watching.
    var isGuarding: Bool { isObserving && timerSnapshot().isFocusRunning }

    var policy: FocusGuardPolicy { FocusGuardPolicy(gracePeriod: gracePeriod, cooldown: cooldown) }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        applyObservation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        applyObservation()
    }

    // MARK: - List editing

    func addApp(_ app: FocusApp) {
        apps = FocusAppList.adding(app, to: apps)
    }

    func removeApp(_ id: FocusApp.ID) {
        apps = FocusAppList.removing(id, from: apps)
    }

    func setApp(_ id: FocusApp.ID, enabled: Bool) {
        apps = FocusAppList.setting(id, enabled: enabled, in: apps)
    }

    func resetApps() {
        apps = FocusApp.defaults
    }

    // MARK: - Events

    /// Entry point for every app activation; exposed for tests.
    func handle(_ activation: FocusActivation) {
        guard !isOwnApp(activation) else { return }
        let activeIDs = FocusAppList.activeIDs(in: apps)
        guard FocusAppList.matches(activation.bundleID, in: activeIDs), let key = activation.bundleID?.lowercased() else {
            lastFocusedApp = activation
            return
        }

        let date = now()
        let decision = policy.decide(
            bundleID: activation.bundleID,
            timer: timerSnapshot(),
            activeIDs: activeIDs,
            lastReminders: lastReminders,
            now: date
        )
        if decision.countsAsDistraction {
            log = log.incremented(on: date, calendar: calendar)
            lastDistraction = activation
        }
        guard case .remind(let minutesLeft) = decision else { return }
        lastReminders[key] = date
        postReminder(for: activation, minutesLeft: minutesLeft)
    }

    /// Re-activates the app that was in front before the distraction.
    func returnToWork() {
        guard let target = lastFocusedApp else { return }
        if !workspace.activate(processID: target.processID) {
            logger.info("Previous app is gone; cannot return to it")
        }
    }

    // MARK: - Private

    private func postReminder(for activation: FocusActivation, minutesLeft: Int) {
        let appName = activation.name ?? "Bu uygulama"
        let hasReturnTarget = lastFocusedApp != nil
        var action: (@MainActor () -> Void)?
        if hasReturnTarget {
            action = { [weak self] in self?.returnToWork() }
        }
        logger.info("Distraction during focus: \(activation.bundleID ?? "?", privacy: .public)")
        alerts.post(NotchAlert(
            module: .status,
            systemImage: Self.alertSymbol,
            title: FocusGuardPolicy.reminderTitle(minutesLeft: minutesLeft),
            subtitle: "\(appName) bekleyebilir.",
            style: .reminder,
            coalescingKey: Self.alertKey,
            autoDismissAfter: Self.alertDuration,
            actionTitle: hasReturnTarget ? "İşe dön" : nil,
            action: action
        ))
    }

    private func isOwnApp(_ activation: FocusActivation) -> Bool {
        guard let ownBundleID else { return false }
        return activation.bundleID?.lowercased() == ownBundleID
    }

    private func isReturnTarget(_ activation: FocusActivation) -> Bool {
        !isOwnApp(activation) && !FocusAppList.matches(activation.bundleID, in: FocusAppList.activeIDs(in: apps))
    }

    private func applyObservation() {
        let shouldObserve = isRunning && isEnabled
        guard shouldObserve != isObserving else { return }
        isObserving = shouldObserve
        if shouldObserve {
            if let front = workspace.frontmostApp, isReturnTarget(front) {
                lastFocusedApp = front
            }
            workspace.startObserving { [weak self] activation in
                self?.handle(activation)
            }
        } else {
            workspace.stopObserving()
            lastReminders = [:]
        }
    }
}
