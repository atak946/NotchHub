import Foundation
import Observation
import OSLog

/// Samples the frontmost app/window every 15 s, maps it to a client via rules and books the time.
@MainActor
@Observable
final class TimeTracker {
    static let sampleInterval: Duration = .seconds(15)
    static let sampleSeconds: TimeInterval = 15
    /// Gaps longer than this (sleep, stalls) are capped so a missed wake-up never books hours.
    static let maxCreditSeconds: TimeInterval = sampleSeconds * 2
    static let defaultIdleThresholdMinutes = 5
    static let idleThresholdRange = 1...60
    private static let secondsPerMinute: TimeInterval = 60

    private enum Keys {
        static let isEnabled = "Insights.trackerEnabled"
        static let rules = "Insights.trackingRules"
        static let idleThresholdMinutes = "Insights.idleThresholdMinutes"
        static let reminderEnabled = "Insights.reminderEnabled"
        static let reminderHour = "Insights.reminderHour"
        static let reminderMinute = "Insights.reminderMinute"
        static let lastSummaryDay = "Insights.lastSummaryDay"
    }

    private(set) var ledger: TimeLedger = .empty
    /// Client matched by the latest counted sample (`nil` when idle or unmatched).
    private(set) var currentClient: String?
    private(set) var isIdle = false
    private(set) var isRunning = false
    private(set) var lastError: String?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            if !isEnabled { resetSampling() }
        }
    }

    var rules: [TrackingRule] {
        didSet { saveRules() }
    }

    var idleThresholdMinutes: Int {
        didSet {
            let valid = min(max(idleThresholdMinutes, Self.idleThresholdRange.lowerBound), Self.idleThresholdRange.upperBound)
            if valid != idleThresholdMinutes { idleThresholdMinutes = valid }
            defaults.set(valid, forKey: Keys.idleThresholdMinutes)
        }
    }

    var reminderEnabled: Bool {
        didSet { defaults.set(reminderEnabled, forKey: Keys.reminderEnabled) }
    }

    var schedule: DailySummarySchedule {
        didSet {
            defaults.set(schedule.hour, forKey: Keys.reminderHour)
            defaults.set(schedule.minute, forKey: Keys.reminderMinute)
        }
    }

    var isAccessibilityTrusted: Bool { permission.isTrusted }
    var todayKey: String { TimeLedgerDay.key(for: clock.now, calendar: calendar) }
    var todayTotalSeconds: Int { ledger.totalSeconds(on: todayKey) }
    var todayClientTotals: [ClientTotal] { ledger.clientTotals(on: todayKey) }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let permission: AccessibilityPermission
    @ObservationIgnored private let probe: any ActivityProbing
    @ObservationIgnored private let store: any TimeLedgerStoring
    @ObservationIgnored private let clock: any InsightsClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let pasteboard: any InsightsPasteboard
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastSampleAt: Date?
    /// Slowed only while nobody is at the screen; Low Power Mode keeps the cadence the credit math relies on.
    @ObservationIgnored private let loop: PowerAwareLoop
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")

    init(
        alerts: NotchAlertCenter,
        permission: AccessibilityPermission,
        probe: any ActivityProbing = SystemActivityProbe(),
        store: any TimeLedgerStoring = FileTimeLedgerStore.makeDefault(),
        clock: any InsightsClock = SystemInsightsClock(),
        calendar: Calendar = .autoupdatingCurrent,
        pasteboard: any InsightsPasteboard = SystemInsightsPasteboard(),
        defaults: UserDefaults = .standard,
        power: (any PowerConditionsProviding)? = nil
    ) {
        self.alerts = alerts
        self.permission = permission
        self.probe = probe
        self.store = store
        self.clock = clock
        self.calendar = calendar
        self.pasteboard = pasteboard
        self.defaults = defaults
        loop = PowerAwareLoop(priority: .awayOnly, power: power, sleep: { try await clock.sleep(for: $0) })
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        rules = Self.loadRules(from: defaults)
        idleThresholdMinutes = defaults.object(forKey: Keys.idleThresholdMinutes) as? Int ?? Self.defaultIdleThresholdMinutes
        reminderEnabled = defaults.object(forKey: Keys.reminderEnabled) as? Bool ?? true
        schedule = DailySummarySchedule(
            hour: defaults.object(forKey: Keys.reminderHour) as? Int ?? DailySummarySchedule.defaultHour,
            minute: defaults.object(forKey: Keys.reminderMinute) as? Int ?? DailySummarySchedule.defaultMinute
        )
    }

    // MARK: - Lifecycle

    func start() {
        guard !loop.isActive else { return }
        loadLedgerIfNeeded()
        isRunning = true
        loop.start { [weak self] in
            guard let self else { return nil }
            await self.sample()
            return Self.sampleInterval
        }
    }

    func stop() {
        loop.stop()
        isRunning = false
        resetSampling()
    }

    /// One sampling tick: credits the time since the previous tick, then checks the daily summary.
    func sample() async {
        loadLedgerIfNeeded()
        defer { checkDailySummary() }
        guard isEnabled else { return }

        let now = clock.now
        let previous = lastSampleAt
        lastSampleAt = now
        let idle = probe.idleSeconds()
        isIdle = idle > TimeInterval(idleThresholdMinutes) * Self.secondsPerMinute
        guard !isIdle else {
            currentClient = nil
            return
        }

        let snapshot = await makeSnapshot(idleSeconds: idle)
        let client = TrackingRuleMatcher.client(for: snapshot, rules: rules)
        currentClient = client
        guard let client, let previous else { return }
        let start = max(previous, now.addingTimeInterval(-Self.maxCreditSeconds))
        let credits = TimeLedgerDay.split(from: start, to: now, calendar: calendar)
        updateLedger(ledger.adding(credits, client: client, appBundleID: snapshot.bundleID))
    }

    // MARK: - Daily summary

    func checkDailySummary() {
        let now = clock.now
        guard reminderEnabled,
              schedule.shouldFire(now: now, lastFiredDay: defaults.string(forKey: Keys.lastSummaryDay), calendar: calendar)
        else { return }
        let day = TimeLedgerDay.key(for: now, calendar: calendar)
        defaults.set(day, forKey: Keys.lastSummaryDay)
        let total = ledger.totalSeconds(on: day)
        guard total > 0 else { return }
        let totals = ledger.clientTotals(on: day)
        alerts.post(NotchAlert(
            module: .status,
            systemImage: "clock.badge.checkmark",
            title: TimeSummaryFormatter.title(totalSeconds: total),
            subtitle: TimeSummaryFormatter.clientLine(totals),
            style: .reminder,
            coalescingKey: "insights.dailySummary",
            autoDismissAfter: NotchAlert.importantDuration,
            actionTitle: String(localized: "Özeti kopyala"),
            action: { [weak self] in self?.copySummary(day: day) }
        ))
    }

    func copySummary(day: String? = nil) {
        let key = day ?? todayKey
        pasteboard.copy(TimeSummaryFormatter.clipboardText(
            day: key, totalSeconds: ledger.totalSeconds(on: key), totals: ledger.clientTotals(on: key)
        ))
    }

    // MARK: - Rules & data

    func addRule() {
        rules = rules + [TrackingRule(client: "", matchType: .windowTitleContains, pattern: "")]
    }

    func removeRule(id: TrackingRule.ID) {
        rules = rules.filter { $0.id != id }
    }

    /// CSV of the calendar week containing `date` (default: today).
    func exportWeekCSV(containing date: Date? = nil) -> String {
        let days = Set(TimeLedgerDay.weekKeys(containing: date ?? clock.now, calendar: calendar))
        return TimeCSVExporter.csv(for: ledger.entries(on: days))
    }

    func resetData() {
        do {
            try store.delete()
            ledger = .empty
            lastError = nil
        } catch {
            logger.error("Could not delete time ledger: \(error.localizedDescription, privacy: .public)")
            lastError = String(localized: "Takip edilen zaman sıfırlanamadı.")
        }
        resetSampling()
    }

    // MARK: - Private

    private func makeSnapshot(idleSeconds: TimeInterval) async -> ActivitySnapshot {
        let bundleID = probe.frontmostBundleID()
        var window: FocusedWindowInfo?
        if permission.refresh() {
            let probe = self.probe
            window = await Task.detached(operation: { probe.focusedWindow() }).value
        }
        return ActivitySnapshot(
            bundleID: bundleID,
            windowTitle: window?.title,
            documentPath: window?.documentPath,
            idleSeconds: idleSeconds
        )
    }

    private func updateLedger(_ updated: TimeLedger) {
        guard updated != ledger else { return }
        ledger = updated
        do {
            try store.save(updated)
            lastError = nil
        } catch {
            logger.error("Could not save time ledger: \(error.localizedDescription, privacy: .public)")
            lastError = String(localized: "Takip edilen zaman kaydedilemedi.")
        }
    }

    private func loadLedgerIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            ledger = try store.load()
        } catch {
            logger.error("Time ledger unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            lastError = String(localized: "Kayıtlı zaman verisi okunamadı ve kenara alındı.")
        }
    }

    private func resetSampling() {
        lastSampleAt = nil
        currentClient = nil
        isIdle = false
    }

    private func saveRules() {
        do {
            defaults.set(try JSONEncoder().encode(rules), forKey: Keys.rules)
        } catch {
            logger.error("Could not save tracking rules: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadRules(from defaults: UserDefaults) -> [TrackingRule] {
        guard let data = defaults.data(forKey: Keys.rules) else { return [] }
        return (try? JSONDecoder().decode([TrackingRule].self, from: data)) ?? []
    }
}
