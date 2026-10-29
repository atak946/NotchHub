import Foundation
import Testing
@testable import NotchHub

struct NotificationPrivacyPolicyTests {
    private func app(_ name: String, _ bundleID: String? = nil) -> NotificationAppIdentity {
        NotificationAppIdentity(bundleID: bundleID, name: name)!
    }

    @Test(arguments: [
        (NotificationContentVisibility.followsGlobal, true, true),
        (.followsGlobal, false, false),
        (.shown, true, true),
        (.shown, false, true),
        (.hidden, true, false),
        (.hidden, false, false),
    ])
    func resolution(visibility: NotificationContentVisibility, global: Bool, expected: Bool) {
        let whatsapp = app("WhatsApp", "net.whatsapp.WhatsApp")
        let rules = NotificationPrivacyPolicy.setting(visibility, for: whatsapp, in: [])
        #expect(NotificationPrivacyPolicy.showsContent(for: whatsapp, rules: rules, globalShowsText: global) == expected)
    }

    @Test func noRulesFollowGlobalToggle() {
        let zoom = app("Zoom")
        #expect(NotificationPrivacyPolicy.visibility(for: zoom, rules: []) == .followsGlobal)
        #expect(NotificationPrivacyPolicy.showsContent(for: zoom, rules: [], globalShowsText: true))
        #expect(!NotificationPrivacyPolicy.showsContent(for: zoom, rules: [], globalShowsText: false))
    }

    @Test func keysPreferBundleIDAndFallBackToNormalizedName() {
        #expect(app("WhatsApp", "net.whatsapp.WhatsApp").key == "bundle:net.whatsapp.whatsapp")
        #expect(app(" Zoom Workplace ").key == "name:zoom")
        #expect(app("zoom.us").key == "name:zoom")
        #expect(app("Mesajlar").key == "name:mesajlar")
        #expect(app("Signal", "bad/../id").bundleID == nil)
        #expect(NotificationAppIdentity(bundleID: "com.a", name: "  ") == nil)
    }

    @Test func bundleIDsDecideWhenBothSidesKnowThem() {
        let rule = NotificationPrivacyPolicy.setting(.hidden, for: app("Teams", "com.microsoft.teams2"), in: [])
        // Same bundle, different name.
        #expect(NotificationPrivacyPolicy.visibility(for: app("Microsoft Teams", "com.microsoft.teams2"), rules: rule) == .hidden)
        // Same name, different bundle: no match.
        #expect(NotificationPrivacyPolicy.visibility(for: app("Teams", "com.microsoft.teams"), rules: rule) == .followsGlobal)
        // Banner without a bundle id falls back to the name.
        #expect(NotificationPrivacyPolicy.visibility(for: app("teams"), rules: rule) == .hidden)
    }

    @Test func bundleRuleWinsOverNameRule() {
        let byName = NotificationPrivacyPolicy.setting(.shown, for: app("Slack"), in: [])
        let rules = byName + [NotificationPrivacyRule(app: app("Slack", "com.tinyspeck.slackmacgap"), visibility: .hidden)]
        #expect(NotificationPrivacyPolicy.visibility(for: app("Slack", "com.tinyspeck.slackmacgap"), rules: rules) == .hidden)
    }

    @Test func settingReplacesAndDefaultRemoves() {
        let whatsapp = app("WhatsApp", "net.whatsapp.WhatsApp")
        let hidden = NotificationPrivacyPolicy.setting(.hidden, for: whatsapp, in: [])
        let shown = NotificationPrivacyPolicy.setting(.shown, for: whatsapp, in: hidden)
        #expect(shown == [NotificationPrivacyRule(app: whatsapp, visibility: .shown)])
        #expect(NotificationPrivacyPolicy.setting(.followsGlobal, for: whatsapp, in: shown).isEmpty)
    }

    @Test func recentAppsDedupeMoveToFrontAndCap() {
        var recents: [NotificationAppIdentity] = []
        for index in 0..<25 {
            recents = NotificationPrivacyPolicy.recording(app("App \(index)"), in: recents)
        }
        #expect(recents.count == NotificationPrivacyPolicy.maxRecentApps)
        #expect(recents.first?.name == "App 24")
        #expect(!recents.contains { $0.name == "App 4" })

        recents = NotificationPrivacyPolicy.recording(app("app 10"), in: recents)
        #expect(recents.count == NotificationPrivacyPolicy.maxRecentApps)
        #expect(recents.first?.name == "app 10")
        #expect(recents.filter { $0.nameKey == "name:app 10" }.count == 1)
    }

    @Test func recordingKeepsKnownBundleID() {
        let first = NotificationPrivacyPolicy.recording(app("WhatsApp", "net.whatsapp.WhatsApp"), in: [])
        let second = NotificationPrivacyPolicy.recording(app("WhatsApp"), in: first)
        #expect(second == [app("WhatsApp", "net.whatsapp.WhatsApp")])
    }

    @Test func listedAppsIncludeRuleOnlyApps() {
        let recents = [app("Zoom")]
        let rules = NotificationPrivacyPolicy.setting(.hidden, for: app("Signal", "org.whispersystems.signal-desktop"), in: [])
            + NotificationPrivacyPolicy.setting(.shown, for: app("zoom.us"), in: [])
        #expect(NotificationPrivacyPolicy.listedApps(recents: recents, rules: rules).map(\.name) == ["Zoom", "Signal"])
    }
}

@MainActor
struct NotificationPrivacySettingsTests {
    private let defaults = makeInsightsTestDefaults()

    @Test func freshInstallHasNoOverrides() {
        let settings = NotificationPrivacySettings(defaults: defaults)
        #expect(settings.rules.isEmpty)
        #expect(settings.recentApps.isEmpty)
    }

    @Test func rulesAndRecentAppsPersist() throws {
        let whatsapp = try #require(NotificationAppIdentity(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"))
        let zoom = try #require(NotificationAppIdentity(bundleID: nil, name: "Zoom"))
        let settings = NotificationPrivacySettings(defaults: defaults)
        settings.setVisibility(.hidden, for: whatsapp)
        settings.recordSeen(whatsapp)
        settings.recordSeen(zoom)

        let reloaded = NotificationPrivacySettings(defaults: defaults)
        #expect(reloaded.visibility(for: whatsapp) == .hidden)
        #expect(reloaded.visibility(for: zoom) == .followsGlobal)
        #expect(reloaded.recentApps == [zoom, whatsapp])
        #expect(!reloaded.showsContent(for: whatsapp, globalShowsText: true))
    }

    @Test func corruptStoredDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "Insights.mirrorPrivacyRules")
        defaults.set(Data("[1,2]".utf8), forKey: "Insights.mirrorRecentApps")
        let settings = NotificationPrivacySettings(defaults: defaults)
        #expect(settings.rules.isEmpty)
        #expect(settings.recentApps.isEmpty)
    }
}
