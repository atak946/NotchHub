import Foundation
import Testing
@testable import NotchHub

@MainActor
struct InsightsFacadeTests {
    private let trust = InsightsFakeTrust(trusted: false)

    private func makeInsights() -> Insights {
        Insights(
            alerts: NotchAlertCenter(), defaults: makeInsightsTestDefaults(), trustChecker: trust,
            badgeReader: InsightsFakeBadgeReader(), activator: InsightsFakeActivator(), probe: InsightsFakeProbe(),
            store: InsightsMemoryLedgerStore(), clock: InsightsTestClock(InsightsTestDates.date(10)),
            calendar: InsightsTestDates.calendar, pasteboard: InsightsFakePasteboard()
        )
    }

    @Test func initAndStartNeverPrompt() {
        let insights = makeInsights()
        insights.start()
        insights.start()
        #expect(trust.promptCount == 0)
        #expect(!insights.isAccessibilityTrusted)
        #expect(!insights.hasCompactIndicator)
        insights.stop()
        insights.stop()
    }

    @Test func explicitRequestPromptsAndOpensSettings() {
        let insights = makeInsights()
        insights.requestAccessibilityAccess()
        #expect(trust.promptCount == 1)
        #expect(trust.settingsOpenCount == 1)
    }

    @Test func trustIsPickedUpOnRefresh() {
        let insights = makeInsights()
        trust.trusted = true
        insights.refreshAccessibilityTrust()
        #expect(insights.isAccessibilityTrusted)
        #expect(insights.unread.isAccessibilityTrusted)
        #expect(insights.timeTracker.isAccessibilityTrusted)
    }
}
