import Foundation
import Testing
@testable import NotchHub

@MainActor
struct UnreadBadgeMonitorTests {
    private let defaults = makeInsightsTestDefaults()
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let clock = InsightsTestClock(Date(timeIntervalSinceReferenceDate: 5_000))
    private let reader = InsightsFakeBadgeReader()
    private let activator = InsightsFakeActivator()

    private func makeMonitor(trust: InsightsFakeTrust) -> UnreadBadgeMonitor {
        UnreadBadgeMonitor(
            alerts: alerts, permission: AccessibilityPermission(checker: trust),
            reader: reader, activator: activator, clock: clock, defaults: defaults
        )
    }

    @Test func defaultsAreSensible() {
        let monitor = makeMonitor(trust: InsightsFakeTrust(trusted: false))
        #expect(monitor.watchedApps == UnreadBadgeMonitor.defaultWatchedApps)
        #expect(monitor.pollSeconds == 5)
        #expect(!monitor.hasCompactIndicator)
    }

    @Test func untrustedNeverReadsDockOrPrompts() async {
        let trust = InsightsFakeTrust(trusted: false)
        let monitor = makeMonitor(trust: trust)
        await monitor.poll()
        #expect(reader.readCount == 0)
        #expect(trust.promptCount == 0)
        #expect(monitor.counts.isEmpty)
    }

    @Test func mapsDockTitlesCaseInsensitively() async {
        reader.badges = ["whatsapp": 3, "Microsoft Outlook": 2, "Finder": 9]
        let monitor = makeMonitor(trust: InsightsFakeTrust(trusted: true))
        await monitor.poll()
        #expect(monitor.totalUnread == 5)
        #expect(monitor.counts.first { $0.app == "WhatsApp" }?.count == 3)
        #expect(monitor.counts.first { $0.app == "Slack" }?.count == 0)
        #expect(monitor.hasCompactIndicator)
        #expect(alerts.current == nil)
    }

    @Test func increasePostsCoalescedAlertWithOpenAction() async throws {
        reader.badges = ["WhatsApp": 1]
        let monitor = makeMonitor(trust: InsightsFakeTrust(trusted: true))
        await monitor.poll()
        reader.badges = ["WhatsApp": 4]
        clock.advance(by: 5)
        await monitor.poll()

        let alert = try #require(alerts.current)
        #expect(alert.title == "WhatsApp · 3 yeni")
        #expect(alert.style == .info)
        #expect(alert.coalescingKey == "insights.unread.whatsapp")
        #expect(alert.actionTitle == "Aç")
        alerts.performAction()
        #expect(activator.activated == ["WhatsApp"])
    }

    @Test func alertsCanBeDisabled() async {
        reader.badges = ["Slack": 0]
        let monitor = makeMonitor(trust: InsightsFakeTrust(trusted: true))
        monitor.alertsEnabled = false
        await monitor.poll()
        reader.badges = ["Slack": 2]
        await monitor.poll()
        #expect(monitor.totalUnread == 2)
        #expect(alerts.current == nil)
    }

    @Test func losingTrustClearsCountsAndBaseline() async {
        let trust = InsightsFakeTrust(trusted: true)
        reader.badges = ["Mail": 2]
        let monitor = makeMonitor(trust: trust)
        await monitor.poll()
        trust.trusted = false
        await monitor.poll()
        #expect(monitor.counts.isEmpty)
        trust.trusted = true
        reader.badges = ["Mail": 5]
        await monitor.poll()
        #expect(alerts.current == nil)
    }

    @Test func watchedAppsAreNormalizedAndPersisted() {
        let monitor = makeMonitor(trust: InsightsFakeTrust(trusted: false))
        monitor.watchedApps = ["  Telegram ", "telegram", "", "Signal"]
        #expect(monitor.watchedApps == ["Telegram", "Signal"])
        monitor.removeWatchedApp("Signal")
        let reloaded = makeMonitor(trust: InsightsFakeTrust(trusted: false))
        #expect(reloaded.watchedApps == ["Telegram"])
    }

    @Test func pollIntervalIsClamped() {
        let monitor = makeMonitor(trust: InsightsFakeTrust(trusted: false))
        monitor.pollSeconds = 0
        #expect(monitor.pollSeconds == UnreadBadgeMonitor.pollSecondsRange.lowerBound)
    }

    @Test func startStopAreIdempotent() {
        let monitor = makeMonitor(trust: InsightsFakeTrust(trusted: false))
        monitor.start()
        monitor.start()
        #expect(monitor.isRunning)
        monitor.stop()
        monitor.stop()
        #expect(!monitor.isRunning)
    }
}

@MainActor
struct UnreadZoomTests {
    @Test func watchesZoomByDefaultWithFriendlyName() {
        #expect(UnreadBadgeMonitor.defaultWatchedApps.contains("zoom.us"))
        #expect(UnreadBadgeMonitor.displayName(for: "zoom.us") == "Zoom")
        #expect(UnreadBadgeMonitor.displayName(for: "Slack") == "Slack")
    }

    @Test func zoomAlertTitleUsesFriendlyName() {
        let increase = UnreadIncrease(app: "zoom.us", count: 3, newMessages: 2)
        #expect(UnreadBadgeMonitor.alertTitle(for: increase) == "Zoom · 2 yeni")
    }
}
