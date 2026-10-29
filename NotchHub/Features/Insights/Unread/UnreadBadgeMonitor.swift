import Foundation
import Observation
import OSLog

/// One watched app with its current unread count.
struct UnreadAppCount: Identifiable, Equatable, Sendable {
    let app: String
    let count: Int

    var id: String { app }
}

/// Polls Dock badges of watched apps while Accessibility is trusted and alerts on new messages.
@MainActor
@Observable
final class UnreadBadgeMonitor {
    static let defaultWatchedApps = ["Microsoft Outlook", "WhatsApp", "Microsoft Teams", "zoom.us", "Slack", "Mail", "Messages"]
    /// Friendlier labels for apps whose Dock title is a bundle name.
    nonisolated private static let displayNames = ["zoom.us": "Zoom"]
    static let defaultPollSeconds = 5
    static let pollSecondsRange = 2...60
    /// Slower re-check of trust while access is missing, so granting it is picked up without a restart.
    static let untrustedRecheckInterval: Duration = .seconds(10)
    static let alertDuration: Duration = .seconds(6)

    private enum Keys {
        static let isEnabled = "Insights.unreadEnabled"
        static let alertsEnabled = "Insights.unreadAlertsEnabled"
        static let pollSeconds = "Insights.unreadPollSeconds"
        static let watchedApps = "Insights.unreadWatchedApps"
    }

    /// Current counts for watched apps, in watched-list order (apps absent from the Dock count 0).
    private(set) var counts: [UnreadAppCount] = []
    private(set) var isRunning = false

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            if !isEnabled { clearCounts() }
        }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    var pollSeconds: Int {
        didSet {
            let valid = Self.clampPollSeconds(pollSeconds)
            if valid != pollSeconds { pollSeconds = valid }
            defaults.set(valid, forKey: Keys.pollSeconds)
        }
    }

    var watchedApps: [String] {
        didSet {
            let valid = Self.normalizedApps(watchedApps)
            if valid != watchedApps { watchedApps = valid }
            defaults.set(valid, forKey: Keys.watchedApps)
            previousCounts = nil
        }
    }

    var totalUnread: Int { counts.reduce(0) { $0 + $1.count } }
    var hasCompactIndicator: Bool { isEnabled && totalUnread > 0 }
    var isAccessibilityTrusted: Bool { permission.isTrusted }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let permission: AccessibilityPermission
    @ObservationIgnored private let reader: any DockBadgeReading
    @ObservationIgnored private let activator: any InsightsAppActivating
    @ObservationIgnored private let clock: any InsightsClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let mirrorLedger: NotificationMirrorLedger
    @ObservationIgnored private var coalescer = UnreadAlertCoalescer()
    @ObservationIgnored private var previousCounts: [String: Int]?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")

    init(
        alerts: NotchAlertCenter,
        permission: AccessibilityPermission,
        reader: any DockBadgeReading = AXDockBadgeReader(),
        activator: any InsightsAppActivating = SystemInsightsAppActivator(),
        clock: any InsightsClock = SystemInsightsClock(),
        defaults: UserDefaults = .standard,
        mirrorLedger: NotificationMirrorLedger = NotificationMirrorLedger()
    ) {
        self.alerts = alerts
        self.mirrorLedger = mirrorLedger
        self.permission = permission
        self.reader = reader
        self.activator = activator
        self.clock = clock
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        pollSeconds = Self.clampPollSeconds(defaults.object(forKey: Keys.pollSeconds) as? Int ?? Self.defaultPollSeconds)
        watchedApps = Self.normalizedApps(defaults.stringArray(forKey: Keys.watchedApps) ?? Self.defaultWatchedApps)
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        isRunning = true
        let clock = self.clock
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                let delay = self.nextDelay()
                try? await clock.sleep(for: delay)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
        previousCounts = nil
    }

    /// One poll: skipped while disabled or untrusted (no AX calls are made then).
    func poll() async {
        guard isEnabled else { return }
        guard permission.refresh() else {
            clearCounts()
            return
        }
        let reader = self.reader
        guard let badges = await Task.detached(operation: { reader.readBadges() }).value else {
            logger.debug("Dock badges unavailable")
            return
        }
        apply(badges: badges)
    }

    // MARK: - Watched apps

    func addWatchedApp(_ name: String) {
        watchedApps = watchedApps + [name]
    }

    func removeWatchedApp(_ name: String) {
        watchedApps = watchedApps.filter { $0 != name }
    }

    func open(app: String) {
        activator.activate(appNamed: app)
    }

    // MARK: - Pure helpers

    /// Maps Dock titles to watched names case-insensitively; missing apps count 0.
    static func watchedCounts(from badges: [String: Int], watched: [String]) -> [String: Int] {
        let lowered = Dictionary(badges.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: max)
        return Dictionary(watched.map { ($0, lowered[$0.lowercased()] ?? 0) }, uniquingKeysWith: max)
    }

    static func alertTitle(for increase: UnreadIncrease) -> String {
        "\(displayName(for: increase.app)) · \(increase.newMessages) yeni"
    }

    nonisolated static func displayName(for app: String) -> String {
        displayNames[app.lowercased()] ?? app
    }

    static func coalescingKey(for app: String) -> String {
        "insights.unread.\(app.lowercased())"
    }

    static func clampPollSeconds(_ value: Int) -> Int {
        min(max(value, pollSecondsRange.lowerBound), pollSecondsRange.upperBound)
    }

    static func normalizedApps(_ apps: [String]) -> [String] {
        var seen = Set<String>()
        return apps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Private

    private func apply(badges: [String: Int]) {
        let current = Self.watchedCounts(from: badges, watched: watchedApps)
        let now = clock.now
        let increases = coalescer.evaluate(previous: previousCounts, current: current, at: now)
        previousCounts = current
        let ordered = watchedApps.map { UnreadAppCount(app: $0, count: current[$0] ?? 0) }
        if ordered != counts { counts = ordered }
        guard alertsEnabled else { return }
        // The notification mirror already named the sender; skip the duplicate "· 1 yeni" alert.
        increases
            .filter { !mirrorLedger.suppressesBadgeAlert(forApp: $0.app, at: now) }
            .forEach(postAlert)
    }

    private func postAlert(for increase: UnreadIncrease) {
        let app = increase.app
        let unit = increase.count == 1 ? "okunmamış mesaj" : "okunmamış mesaj"
        alerts.post(NotchAlert(
            module: .status,
            systemImage: "bubble.left.and.text.bubble.right.fill",
            title: Self.alertTitle(for: increase),
            subtitle: "\(increase.count) \(unit)",
            style: .info,
            coalescingKey: Self.coalescingKey(for: app),
            autoDismissAfter: Self.alertDuration,
            actionTitle: "Aç",
            action: { [weak self] in self?.open(app: app) },
            appBundleID: KnownApps.bundleID(forName: app),
            appName: Self.displayName(for: app)
        ))
    }

    private func clearCounts() {
        previousCounts = nil
        if !counts.isEmpty { counts = [] }
    }

    private func nextDelay() -> Duration {
        permission.isTrusted ? .seconds(pollSeconds) : Self.untrustedRecheckInterval
    }
}
