import Foundation
import Testing
@testable import NotchHub

struct NotificationBannerParserTests {
    @Test func appNameIsFirstDescriptionComponent() {
        let description = "Betik Düzenleyici, Ahmet Yılmaz, Test, Toplantı linkini atar mısın?"
        #expect(NotificationBannerParser.appName(fromDescription: description) == "Betik Düzenleyici")
        #expect(NotificationBannerParser.appName(fromDescription: "  WhatsApp ") == "WhatsApp")
        #expect(NotificationBannerParser.appName(fromDescription: "") == nil)
        #expect(NotificationBannerParser.appName(fromDescription: nil) == nil)
    }

    @Test func mapsFields() throws {
        let raw = RawNotificationBanner(
            identifier: "9FACE2D4", description: "WhatsApp, Ahmet Yılmaz, Test, Merhaba",
            title: "Ahmet Yılmaz", subtitle: "Test", body: "Merhaba\n  dünya"
        )
        let banner = try #require(NotificationBannerParser.banner(from: raw))
        #expect(banner == NotificationBanner(
            id: "9FACE2D4", app: "WhatsApp", title: "Ahmet Yılmaz", subtitle: "Test", body: "Merhaba dünya"
        ))
    }

    @Test func missingSubtitleAndTitleFallBack() throws {
        let raw = RawNotificationBanner(identifier: "x", description: "Slack, Ayşe, selam", title: nil, body: "selam")
        let banner = try #require(NotificationBannerParser.banner(from: raw))
        #expect(banner.subtitle == nil)
        #expect(banner.title == "Ayşe")
    }

    @Test func rejectsBannersWithoutAppOrContent() {
        #expect(NotificationBannerParser.banner(from: RawNotificationBanner(identifier: "a", title: "T")) == nil)
        #expect(NotificationBannerParser.banner(from: RawNotificationBanner(identifier: "a", description: "Zoom")) == nil)
    }

    @Test func fieldsAreCapped() throws {
        let long = String(repeating: "a", count: 5_000)
        let raw = RawNotificationBanner(identifier: "a", description: "Zoom", title: long)
        let banner = try #require(NotificationBannerParser.banner(from: raw))
        #expect(banner.title.count == NotificationBannerParser.maxFieldLength)
    }

    @Test func directMessageSenderIsTitle() {
        let sender = NotificationBannerParser.sender(of: InsightsBanners.make("1"))
        #expect(sender == NotificationSender(name: "Ahmet Yılmaz", message: "Toplantı linkini atar mısın?"))
    }

    @Test func groupMessageCombinesSenderAndGroup() {
        let banner = InsightsBanners.make("1", title: "Proje Grubu", body: "Ahmet: Toplantı 15:00'te")
        let sender = NotificationBannerParser.sender(of: banner)
        #expect(sender == NotificationSender(name: "Ahmet · Proje Grubu", message: "Toplantı 15:00'te"))
    }

    @Test func groupPrefixMatchingTitleIsNotRepeated() {
        let banner = InsightsBanners.make("1", title: "Ahmet", body: "Ahmet: selam")
        #expect(NotificationBannerParser.sender(of: banner).name == "Ahmet")
    }

    @Test func ordinaryColonsAreNotSenders() {
        #expect(NotificationBannerParser.splitSenderPrefix("Saat 12:30 uygun mu?") == nil)
        #expect(NotificationBannerParser.splitSenderPrefix("Bak https://example.com") == nil)
        #expect(NotificationBannerParser.splitSenderPrefix("Bu çok uzun bir giriş cümlesi gerçekten: evet") == nil)
        #expect(NotificationBannerParser.splitSenderPrefix("Ahmet: ") == nil)
        #expect(NotificationBannerParser.splitSenderPrefix("~ Ayşe K: tamam")?.name == "~ Ayşe K")
    }

    @Test func picksLocalizedCloseAction() {
        let actions = [
            "AXPress",
            "Name:Ayrıntıları Göster\nTarget:0x0\nSelector:(null)",
            "Name:Göster\nTarget:0x0\nSelector:(null)",
            "Name:Kapat\nTarget:0x0\nSelector:(null)",
        ]
        #expect(NotificationBannerParser.closeActionName(from: actions) == actions[3])
        #expect(NotificationBannerParser.closeActionName(from: ["AXPress", "Name:Close\nTarget:0x0"]) == "Name:Close\nTarget:0x0")
        #expect(NotificationBannerParser.closeActionName(from: ["AXPress", "Name:Göster"]) == nil)
    }
}
