import Foundation
import Testing
@testable import NotchHub

struct NotificationMirrorPolicyTests {
    private let keywords = NotificationMirrorPolicy.defaultKeywords

    @Test(arguments: [
        ("WhatsApp", "whatsapp"), ("zoom.us", "zoom"), ("Zoom Workplace", "zoom"), ("Microsoft Teams", "teams"),
        ("Microsoft Outlook", "outlook"), ("Slack", "slack"), (" Telegram ", "telegram"),
    ])
    func canonicalKey(app: String, key: String) {
        #expect(MessagingApp.canonicalKey(for: app) == key)
    }

    @Test func keywordMatchingIsCaseInsensitiveContains() {
        #expect(NotificationMirrorPolicy.matches(app: "zoom.us", keywords: keywords))
        #expect(NotificationMirrorPolicy.matches(app: "Zoom Workplace", keywords: keywords))
        #expect(NotificationMirrorPolicy.matches(app: "WHATSAPP", keywords: keywords))
        #expect(!NotificationMirrorPolicy.matches(app: "Betik Düzenleyici", keywords: keywords))
        #expect(!NotificationMirrorPolicy.matches(app: "Slack", keywords: []))
    }

    @Test func messagingSubtitleWithAndWithoutText() {
        let banner = InsightsBanners.make("1")
        let shown = NotificationMirrorPolicy.content(for: banner, keywords: keywords, showsMessageText: true)
        #expect(shown.title == "Ahmet Yılmaz")
        #expect(shown.subtitle == "Toplantı linkini atar mısın?")
        #expect(shown.systemImage == "message.fill")
        #expect(shown.coalescingKey == "insights.mirror.whatsapp.ahmet yılmaz")
        #expect(shown.messagingKey == "whatsapp")
        let hidden = NotificationMirrorPolicy.content(for: banner, keywords: keywords, showsMessageText: false)
        #expect(hidden.subtitle == "Yeni mesaj")
    }

    @Test func genericAppUsesTitleAndSubtitleOrBody() {
        let banner = InsightsBanners.make("1", app: "Betik Düzenleyici", title: "Derleme", subtitle: "Test", body: "Bitti")
        let content = NotificationMirrorPolicy.content(for: banner, keywords: keywords, showsMessageText: true)
        #expect(content.title == "Derleme")
        #expect(content.subtitle == "Test")
        #expect(content.systemImage == MessagingApp.fallbackSystemImage)
        #expect(content.messagingKey == nil)
        let noSubtitle = InsightsBanners.make("2", app: "Takvim", title: "Toplantı", body: "10:00")
        #expect(NotificationMirrorPolicy.content(for: noSubtitle, keywords: keywords, showsMessageText: true)
            .subtitle == "10:00")
        #expect(NotificationMirrorPolicy.content(for: noSubtitle, keywords: keywords, showsMessageText: false)
            .subtitle == "Yeni bildirim")
    }

    @Test func longBodyIsTruncatedToLimit() {
        let body = String(repeating: "kelime ", count: 40)
        let subtitle = NotificationMirrorPolicy.subtitle(text: body, placeholder: "x")
        let text = subtitle
        #expect(text.count <= NotificationMirrorPolicy.maxSubtitleTextLength)
        #expect(text.hasSuffix("…"))
        #expect(NotificationMirrorPolicy.truncated("kısa", limit: 80) == "kısa")
        #expect(NotificationMirrorPolicy.truncated("abcdef", limit: 4) == "abc…")
    }

    @Test func decisionsCoverScopeSelfAndAlertGate() {
        let whatsapp = InsightsBanners.make("1")
        let script = InsightsBanners.make("2", app: "Betik Düzenleyici")
        let own = InsightsBanners.make("3", app: "NotchHub")
        func decide(_ banner: NotificationBanner, _ scope: NotificationMirrorScope, canPost: Bool = true, hides: Bool = true) -> NotificationMirrorDecision {
            NotificationMirrorPolicy.decision(for: banner, scope: scope, keywords: keywords, canPost: canPost, hidesNative: hides)
        }
        #expect(decide(whatsapp, .allApps) == .mirror(dismissNative: true))
        #expect(decide(script, .allApps) == .mirror(dismissNative: true))
        #expect(decide(script, .messagingOnly) == .ignore)
        #expect(decide(whatsapp, .messagingOnly) == .mirror(dismissNative: true))
        #expect(decide(whatsapp, .allApps, hides: false) == .mirror(dismissNative: false))
        #expect(decide(own, .allApps) == .ignore)
        #expect(decide(whatsapp, .allApps, canPost: false) == .ignore)
    }

    @Test func keywordsAreNormalized() {
        #expect(NotificationMirrorPolicy.normalizedKeywords([" Zoom ", "zoom", "", "Signal"]) == ["zoom", "signal"])
    }

    @Test func boundedIDSetForgetsOldest() {
        var set = BoundedIDSet(capacity: 2)
        let first = set.insert("a")
        let again = set.insert("a")
        #expect(first)
        #expect(!again)
        set.insert("b")
        set.insert("c")
        #expect(set.count == 2)
        #expect(!set.contains("a"))
        #expect(set.contains("c"))
    }

    @MainActor
    @Test func ledgerSuppressesWithinWindowByCanonicalKey() {
        let ledger = NotificationMirrorLedger()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        ledger.record(appKey: "teams", at: start)
        #expect(ledger.suppressesBadgeAlert(forApp: "Microsoft Teams", at: start.addingTimeInterval(14)))
        #expect(!ledger.suppressesBadgeAlert(forApp: "Microsoft Teams", at: start.addingTimeInterval(15)))
        #expect(!ledger.suppressesBadgeAlert(forApp: "Slack", at: start))
    }
}

struct NotificationMirrorOpenPolicyTests {
    @Test func scriptNotificationsCannotBeOpened() {
        #expect(!NotificationMirrorPolicy.canOpen(app: "Betik Düzenleyici"))
        #expect(!NotificationMirrorPolicy.canOpen(app: "script editor"))
        #expect(NotificationMirrorPolicy.canOpen(app: "WhatsApp"))
    }
}
