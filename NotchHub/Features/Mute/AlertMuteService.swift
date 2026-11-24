import Foundation
import Observation
import OSLog

/// Mutes notch alerts by hand, during meetings or during Pomodoro focus; what arrives meanwhile is held
/// in memory and summarized once muting ends.
@MainActor
@Observable
final class AlertMuteService {
    static let maxHeldAlerts = 50
    private static let maxSummarySources = 3
    private static let summaryKey = "mute.summary"

    private enum Keys {
        static let manualUntil = "AlertMute.manualUntil"
        static let mutesInMeetings = "AlertMute.mutesInMeetings"
        static let mutesInFocus = "AlertMute.mutesInFocus"
        static let allowsTimeSensitive = "AlertMute.allowsTimeSensitive"
    }

    var mutesInMeetings: Bool {
        didSet { defaults.set(mutesInMeetings, forKey: Keys.mutesInMeetings) }
    }

    var mutesInFocus: Bool {
        didSet { defaults.set(mutesInFocus, forKey: Keys.mutesInFocus) }
    }

    /// Lets meeting reminders and finished timers through.
    var allowsTimeSensitive: Bool {
        didSet { defaults.set(allowsTimeSensitive, forKey: Keys.allowsTimeSensitive) }
    }

    private(set) var reason: AlertMuteReason?
    /// Alerts that arrived while muted, oldest first; kept until the next mute so they stay in the menu.
    private(set) var held: [NotchAlert] = []

    var isMuted: Bool { reason != nil }

    private var manualUntil: Date? {
        didSet { defaults.set(manualUntil, forKey: Keys.manualUntil) }
    }
    /// The user unmuted during a meeting or focus; holds until that meeting or focus ends.
    private var overridesAutomatic = false

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let isInMeeting: @MainActor () -> Bool
    @ObservationIgnored private let isInFocus: @MainActor () -> Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Mute")

    init(
        alerts: NotchAlertCenter,
        isInMeeting: @escaping @MainActor () -> Bool,
        isInFocus: @escaping @MainActor () -> Bool,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.alerts = alerts
        self.isInMeeting = isInMeeting
        self.isInFocus = isInFocus
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        mutesInMeetings = defaults.object(forKey: Keys.mutesInMeetings) as? Bool ?? false
        mutesInFocus = defaults.object(forKey: Keys.mutesInFocus) as? Bool ?? false
        allowsTimeSensitive = defaults.object(forKey: Keys.allowsTimeSensitive) as? Bool ?? true
        manualUntil = defaults.object(forKey: Keys.manualUntil) as? Date
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        alerts.shouldPresent = { [weak self] alert in
            guard let self else { return true }
            return AlertMutePolicy.shouldPresent(
                alert.muteBehavior, isMuted: self.isMuted, allowsTimeSensitive: self.allowsTimeSensitive
            )
        }
        alerts.onSuppressed = { [weak self] in self?.hold($0) }
        track()
        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        expiryTask?.cancel()
        alerts.shouldPresent = { _ in true }
        alerts.onSuppressed = { _ in }
        reason = nil
    }

    // MARK: - Actions

    func mute(for duration: AlertMuteDuration) {
        manualUntil = duration.end(from: now(), calendar: calendar)
        refresh()
    }

    /// Ends manual muting and, until it is over, the current meeting's or focus phase's muting.
    func unmute() {
        manualUntil = nil
        overridesAutomatic = isAutomaticActive
        refresh()
    }

    /// Plays the held alerts in the notch again.
    func showHeld() {
        let pending = held
        held = []
        pending.suffix(NotchAlertCenter.maxQueuedAlerts).forEach(alerts.post)
    }

    func clearHeld() {
        held = []
    }

    // MARK: - Private

    private var isMeetingActive: Bool { mutesInMeetings && isInMeeting() }
    private var isFocusActive: Bool { mutesInFocus && isInFocus() }
    private var isAutomaticActive: Bool { isMeetingActive || isFocusActive }

    private func track() {
        withObservationTracking {
            // Read both: a short-circuited `||` would leave one of them unobserved.
            _ = isMeetingActive
            _ = isFocusActive
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.track()
                self.refresh()
            }
        }
    }

    private func refresh() {
        let date = now()
        if let manualUntil, manualUntil <= date { self.manualUntil = nil }
        if !isAutomaticActive { overridesAutomatic = false }
        let newReason = AlertMutePolicy.reason(
            manualUntil: manualUntil,
            now: date,
            isInMeeting: isMeetingActive,
            isInFocus: isFocusActive,
            overridesAutomatic: overridesAutomatic
        )
        scheduleExpiry(from: date)
        guard newReason != reason else { return }
        let wasMuted = isMuted
        reason = newReason
        if isMuted, !wasMuted {
            logger.info("Alerts muted")
            held = []
            alerts.discardSuppressed()
        } else if !isMuted, wasMuted {
            logger.info("Alerts unmuted, \(self.held.count, privacy: .public) held")
            postSummary()
        }
    }

    private func scheduleExpiry(from date: Date) {
        expiryTask?.cancel()
        guard let manualUntil, manualUntil != .distantFuture else { return }
        let delay = Duration.seconds(manualUntil.timeIntervalSince(date))
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.refresh()
        }
    }

    private func hold(_ alert: NotchAlert) {
        guard AlertMutePolicy.isHeld(alert.muteBehavior) else { return }
        held = Array((held + [alert]).suffix(Self.maxHeldAlerts))
    }

    private func postSummary() {
        guard !held.isEmpty else { return }
        let count = held.count
        alerts.post(NotchAlert(
            module: nil,
            systemImage: "bell.badge.fill",
            title: String(localized: "Susturulurken \(count) bildirim geldi"),
            subtitle: AlertMutePolicy.summary(of: held.map(\.sourceLabel), maxSources: Self.maxSummarySources),
            style: .info,
            coalescingKey: Self.summaryKey,
            autoDismissAfter: NotchAlert.importantDuration,
            actionTitle: String(localized: "Göster"),
            action: { [weak self] in self?.showHeld() }
        ))
    }
}
