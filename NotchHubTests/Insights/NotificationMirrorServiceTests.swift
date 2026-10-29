import Foundation
import Testing
@testable import NotchHub

@MainActor
struct NotificationMirrorServiceTests {
    private let defaults = makeInsightsTestDefaults()
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let clock = InsightsTestClock(Date(timeIntervalSinceReferenceDate: 5_000))
    private let reader = InsightsFakeBannerReader()
    private let observer = InsightsFakeBannerObserver()
    private let activator = InsightsFakeActivator()

    private func makeService(
        trust: InsightsFakeTrust = InsightsFakeTrust(trusted: true), canPost: Bool = true
    ) -> NotificationMirrorService {
        let service = NotificationMirrorService(
            alerts: alerts, permission: AccessibilityPermission(checker: trust), reader: reader,
            observer: observer, activator: activator, clock: clock, defaults: defaults
        )
        service.shouldPostAlert = { canPost }
        return service
    }

    /// First poll baselines with nothing on screen, so the next banners count as new.
    private func makeBaselinedService(canPost: Bool = true) async -> NotificationMirrorService {
        let service = makeService(canPost: canPost)
        await service.poll()
        return service
    }

    @Test func defaultsAreSensible() {
        let service = makeService()
        #expect(service.isEnabled)
        #expect(service.showsMessageText)
        #expect(service.hidesNativeBanners)
        #expect(service.scope == .allApps)
        #expect(service.keywords == NotificationMirrorPolicy.defaultKeywords)
    }

    @Test func bannerOnScreenAtStartupIsBaselined() async {
        reader.show([InsightsBanners.make("old")])
        let service = makeService()
        await service.poll()
        await service.poll()
        #expect(alerts.current == nil)
        #expect(reader.dismissedIDs.isEmpty)
    }

    @Test func newBannerAlertsOnceAndIsDismissed() async throws {
        let service = await makeBaselinedService()
        reader.show([InsightsBanners.make("b1")])
        await service.poll()
        await service.poll()

        let alert = try #require(alerts.current)
        #expect(alert.title == "Ahmet Yılmaz")
        #expect(alert.subtitle == "Toplantı linkini atar mısın?")
        #expect(alert.module == .status)
        #expect(alert.style == .info)
        #expect(alert.autoDismissAfter == .seconds(6))
        #expect(alerts.queue.isEmpty)
        #expect(reader.dismissedIDs == ["b1"])
        #expect(service.lastMirrored?.title == "Ahmet Yılmaz")
        alerts.performAction()
        #expect(activator.activated == ["WhatsApp"])
    }

    @Test func keepsNativeBannerWhenHidingIsOff() async {
        let service = await makeBaselinedService()
        service.hidesNativeBanners = false
        reader.show([InsightsBanners.make("b1")])
        await service.poll()
        #expect(alerts.current != nil)
        #expect(reader.dismissedIDs.isEmpty)
    }

    @Test func alertsDisabledNeitherPostsNorDismisses() async {
        let service = await makeBaselinedService(canPost: false)
        reader.show([InsightsBanners.make("b1")])
        await service.poll()
        #expect(alerts.current == nil)
        #expect(reader.dismissedIDs.isEmpty)
    }

    @Test func unwiredAlertGateIsTreatedAsDisabled() async {
        let service = makeService()
        service.shouldPostAlert = nil
        await service.poll()
        reader.show([InsightsBanners.make("b1")])
        await service.poll()
        #expect(alerts.current == nil)
        #expect(reader.dismissedIDs.isEmpty)
    }

    @Test func ownNotificationsAreNeverTouched() async {
        let service = await makeBaselinedService()
        reader.show([InsightsBanners.make("own", app: "NotchHub", title: "Süre doldu")])
        await service.poll()
        #expect(alerts.current == nil)
        #expect(reader.dismissedIDs.isEmpty)
    }

    @Test func messagingOnlyScopeSkipsOtherApps() async throws {
        let service = await makeBaselinedService()
        service.scope = .messagingOnly
        reader.show([
            InsightsBanners.make("s1", app: "Betik Düzenleyici", title: "Derleme"),
            InsightsBanners.make("z1", app: "zoom.us", title: "Ayşe", body: "Toplantı başladı"),
        ])
        await service.poll()
        let alert = try #require(alerts.current)
        #expect(alert.title == "Ayşe")
        #expect(alert.subtitle == "Toplantı başladı")
        #expect(reader.dismissedIDs == ["z1"])
    }

    @Test func allAppsScopeMirrorsGenericBanner() async throws {
        let service = await makeBaselinedService()
        reader.show([InsightsBanners.make("s1", app: "Betik Düzenleyici", title: "Ahmet Yılmaz", subtitle: "Test", body: "Merhaba")])
        await service.poll()
        let alert = try #require(alerts.current)
        #expect(alert.subtitle == "Test")
        #expect(alert.systemImage == MessagingApp.fallbackSystemImage)
        #expect(reader.dismissedIDs == ["s1"])
        _ = service
    }

    @Test func hidingMessageTextUsesPlaceholder() async throws {
        let service = await makeBaselinedService()
        service.showsMessageText = false
        reader.show([InsightsBanners.make("b1", title: "Proje Grubu", body: "Ahmet: gizli")])
        await service.poll()
        let alert = try #require(alerts.current)
        #expect(alert.title == "Ahmet · Proje Grubu")
        #expect(alert.subtitle == "Yeni mesaj")
    }

    @Test func untrustedNeverReadsAndResetsBaseline() async {
        let trust = InsightsFakeTrust(trusted: false)
        let service = makeService(trust: trust)
        service.shouldPostAlert = { true }
        reader.show([InsightsBanners.make("b1")])
        await service.poll()
        #expect(reader.readCount == 0)
        #expect(trust.promptCount == 0)
        trust.trusted = true
        await service.poll()
        #expect(alerts.current == nil)
    }

    @Test func disablingStopsReadingAndRebaselines() async {
        let service = await makeBaselinedService()
        service.isEnabled = false
        reader.show([InsightsBanners.make("b1")])
        await service.poll()
        #expect(reader.readCount == 1)
        service.isEnabled = true
        await service.poll()
        #expect(alerts.current == nil)
    }

    @Test func observerAttachesWhileRunningAndDetachesOnStop() async {
        let service = makeService()
        service.start()
        await service.poll()
        #expect(observer.attachCount >= 1)
        service.stop()
        #expect(observer.detachCount >= 1)
        #expect(!service.isRunning)
    }

    @Test func settingsPersist() {
        let service = makeService()
        service.scope = .messagingOnly
        service.hidesNativeBanners = false
        service.addKeyword(" Telegram ")
        service.removeKeyword("slack")
        let reloaded = makeService()
        #expect(reloaded.scope == .messagingOnly)
        #expect(!reloaded.hidesNativeBanners)
        #expect(reloaded.keywords == ["whatsapp", "zoom", "teams", "outlook", "telegram"])
    }
}

@MainActor
struct UnreadBadgeSuppressionTests {
    private let defaults = makeInsightsTestDefaults()
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let clock = InsightsTestClock(Date(timeIntervalSinceReferenceDate: 5_000))
    private let badges = InsightsFakeBadgeReader()
    private let ledger = NotificationMirrorLedger()

    private func makeMonitor() -> UnreadBadgeMonitor {
        UnreadBadgeMonitor(
            alerts: alerts, permission: AccessibilityPermission(checker: InsightsFakeTrust(trusted: true)),
            reader: badges, activator: InsightsFakeActivator(), clock: clock, defaults: defaults, mirrorLedger: ledger
        )
    }

    @Test func badgeAlertSkippedRightAfterMirror() async {
        badges.badges = ["WhatsApp": 0]
        let monitor = makeMonitor()
        await monitor.poll()
        ledger.record(appKey: "whatsapp", at: clock.now)
        clock.advance(by: 5)
        badges.badges = ["WhatsApp": 1]
        await monitor.poll()
        #expect(alerts.current == nil)
        #expect(monitor.totalUnread == 1)
    }

    @Test func badgeAlertStillFiresWhenMirrorIsStaleOrOtherApp() async {
        badges.badges = ["Microsoft Teams": 0, "Slack": 0]
        let monitor = makeMonitor()
        await monitor.poll()
        ledger.record(appKey: "teams", at: clock.now)
        clock.advance(by: 20)
        badges.badges = ["Microsoft Teams": 1, "Slack": 0]
        await monitor.poll()
        #expect(alerts.current?.title == "Microsoft Teams · 1 yeni")
    }
}
