import Foundation
import Testing
@testable import NotchHub

@MainActor
struct TimeTrackerTests {
    private let defaults = makeInsightsTestDefaults()
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let clock = InsightsTestClock(InsightsTestDates.date(10))
    private let probe = InsightsFakeProbe()
    private let store = InsightsMemoryLedgerStore()
    private let pasteboard = InsightsFakePasteboard()
    private let rule = TrackingRule(client: "Northwind", matchType: .windowTitleContains, pattern: "NorthwindServices")

    private func makeTracker(trusted: Bool = true) -> TimeTracker {
        let tracker = TimeTracker(
            alerts: alerts, permission: AccessibilityPermission(checker: InsightsFakeTrust(trusted: trusted)),
            probe: probe, store: store, clock: clock, calendar: InsightsTestDates.calendar,
            pasteboard: pasteboard, defaults: defaults
        )
        tracker.rules = [rule]
        return tracker
    }

    private func sample(_ tracker: TimeTracker, times: Int, every seconds: TimeInterval = 15) async {
        for _ in 0..<times {
            await tracker.sample()
            clock.advance(by: seconds)
        }
    }

    @Test func creditsMatchedTimeBetweenSamples() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "Program.cs — NorthwindServices")
        let tracker = makeTracker()
        await sample(tracker, times: 5)
        #expect(tracker.todayTotalSeconds == 60)
        #expect(tracker.currentClient == "Northwind")
        #expect(store.saved?.entries == [
            TimeLedgerEntry(day: "2026-10-28", client: "Northwind", appBundleID: "com.microsoft.VSCode", seconds: 60),
        ])
    }

    @Test func unmatchedActivityIsNotCounted() async {
        probe.set(bundleID: "com.apple.Safari", title: "News")
        let tracker = makeTracker()
        await sample(tracker, times: 4)
        #expect(tracker.todayTotalSeconds == 0)
        #expect(tracker.currentClient == nil)
        #expect(store.saveCount == 0)
    }

    @Test func idleTimeIsExcluded() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        let tracker = makeTracker()
        await sample(tracker, times: 3)
        probe.setIdle(301)
        await sample(tracker, times: 4)
        #expect(tracker.isIdle)
        probe.setIdle(2)
        await sample(tracker, times: 2)
        // 2 credited before idle, 1 on the first active sample after idle (15 s since the idle tick), 1 more.
        #expect(tracker.todayTotalSeconds == 30 + 15 + 15)
        #expect(!tracker.isIdle)
    }

    @Test func idleThresholdIsConfigurable() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices", idle: 90)
        let tracker = makeTracker()
        tracker.idleThresholdMinutes = 1
        await sample(tracker, times: 3)
        #expect(tracker.todayTotalSeconds == 0)
    }

    @Test func longGapsAreCapped() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        let tracker = makeTracker()
        await tracker.sample()
        clock.advance(by: 3600)
        await tracker.sample()
        #expect(tracker.todayTotalSeconds == Int(TimeTracker.maxCreditSeconds))
    }

    @Test func midnightSplitsCreditBetweenDays() async {
        clock.set(InsightsTestDates.date(23, 59, 50))
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        let tracker = makeTracker()
        await sample(tracker, times: 2)
        #expect(tracker.ledger.totalSeconds(on: "2026-10-28") == 10)
        #expect(tracker.ledger.totalSeconds(on: "2026-10-29") == 5)
        #expect(tracker.todayKey == "2026-10-29")
    }

    @Test func untrustedSkipsWindowReadsButKeepsAppRules() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        let tracker = makeTracker(trusted: false)
        tracker.rules = [rule, TrackingRule(client: "Code", matchType: .appBundleID, pattern: "com.microsoft.VSCode")]
        await sample(tracker, times: 2)
        #expect(probe.windowReads == 0)
        #expect(tracker.todayClientTotals == [ClientTotal(client: "Code", seconds: 15)])
    }

    @Test func disabledTrackerDoesNotSample() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        let tracker = makeTracker()
        tracker.isEnabled = false
        await sample(tracker, times: 3)
        #expect(tracker.todayTotalSeconds == 0)
        #expect(probe.windowReads == 0)
    }

    @Test func rulesAndSettingsPersist() {
        let tracker = makeTracker()
        tracker.idleThresholdMinutes = 10
        tracker.schedule = DailySummarySchedule(hour: 17, minute: 30)
        let reloaded = TimeTracker(
            alerts: alerts, permission: AccessibilityPermission(checker: InsightsFakeTrust(trusted: false)),
            probe: probe, store: store, clock: clock, calendar: InsightsTestDates.calendar,
            pasteboard: pasteboard, defaults: defaults
        )
        #expect(reloaded.rules == [rule])
        #expect(reloaded.idleThresholdMinutes == 10)
        #expect(reloaded.schedule.hour == 17 && reloaded.schedule.minute == 30)
    }

    @Test func loadsPersistedLedgerOnStart() async {
        let existing = TimeLedger.empty.adding(seconds: 600, client: "Globex", appBundleID: "com.a", day: "2026-10-28")
        try? store.save(existing)
        let tracker = makeTracker()
        tracker.start()
        #expect(tracker.todayClientTotals == [ClientTotal(client: "Globex", seconds: 600)])
        tracker.stop()
        tracker.stop()
        #expect(!tracker.isRunning)
    }

    @Test func dailySummaryPostsOnceAndCopies() async throws {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        clock.set(InsightsTestDates.date(17, 59, 30))
        let tracker = makeTracker()
        await sample(tracker, times: 2)
        #expect(alerts.current == nil)
        await tracker.sample()

        let alert = try #require(alerts.current)
        #expect(alert.title == "Bugün: 0dk takip edildi")
        #expect(alert.subtitle == "Northwind 0dk")
        #expect(alert.actionTitle == "Özeti kopyala")
        #expect(alert.style == .reminder)
        alerts.performAction()
        #expect(pasteboard.copied == ["2026-10-28: 0dk takip edildi\n- Northwind: 0dk"])

        clock.advance(by: 15)
        await tracker.sample()
        #expect(alerts.current == nil)
    }

    @Test func noSummaryOnWeekendOrWhenDisabled() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        clock.set(InsightsTestDates.date(2026, 10, 31, 17, 59, 30))
        let tracker = makeTracker()
        await sample(tracker, times: 4)
        #expect(alerts.current == nil)

        clock.set(InsightsTestDates.date(2026, 11, 2, 18, 0, 5))
        tracker.reminderEnabled = false
        await tracker.sample()
        #expect(alerts.current == nil)
    }

    @Test func exportsCurrentWeekOnly() async {
        let ledger = TimeLedger.empty
            .adding(seconds: 600, client: "Northwind", appBundleID: "com.a", day: "2026-10-26")
            .adding(seconds: 600, client: "Northwind", appBundleID: "com.a", day: "2026-10-25")
        try? store.save(ledger)
        let tracker = makeTracker()
        tracker.start()
        tracker.stop()
        #expect(tracker.exportWeekCSV() == "Tarih,Müşteri,Uygulama,Dakika\r\n2026-10-26,Northwind,com.a,10.0\r\n")
    }

    @Test func resetClearsLedgerAndStore() async {
        probe.set(bundleID: "com.microsoft.VSCode", title: "NorthwindServices")
        let tracker = makeTracker()
        await sample(tracker, times: 3)
        tracker.resetData()
        #expect(tracker.ledger == .empty)
        #expect(store.saved == nil)
        #expect(tracker.rules == [rule])
    }
}
