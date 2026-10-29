import Foundation
import Testing
@testable import NotchHub

struct CompactUnreadSummaryTests {
    private func counts(_ pairs: [(String, Int)]) -> [UnreadAppCount] {
        pairs.map { UnreadAppCount(app: $0.0, count: $0.1) }
    }

    @Test func emptyWhenNothingUnread() {
        let summary = CompactUnreadSummary(counts: counts([("WhatsApp", 0), ("Slack", 0)]))
        #expect(summary.isEmpty)
        #expect(summary.overflow == 0)
        #expect(summary.tooltip.isEmpty)
    }

    @Test func busiestFirstWithOverflowAndWatchedOrderTooltip() {
        let summary = CompactUnreadSummary(counts: counts([("WhatsApp", 1), ("zoom.us", 2), ("Slack", 0), ("Mail", 5)]))
        #expect(summary.shown.map(\.app) == ["Mail", "zoom.us"])
        #expect(summary.overflow == 1)
        #expect(summary.tooltip == "WhatsApp: 1, Zoom: 2, Mail: 5")
    }

    @Test func tiesKeepWatchedOrder() {
        let summary = CompactUnreadSummary(counts: counts([("WhatsApp", 1), ("Slack", 1)]))
        #expect(summary.shown.map(\.app) == ["WhatsApp", "Slack"])
        #expect(summary.overflow == 0)
    }

    @Test func badgeTextIsCapped() {
        #expect(CompactUnreadSummary.badgeText(for: 7) == "7")
        #expect(CompactUnreadSummary.badgeText(for: 150) == "99+")
    }

    @Test func knownAppBundleIDs() {
        #expect(KnownApps.bundleID(forName: "WhatsApp") == "net.whatsapp.WhatsApp")
        #expect(KnownApps.bundleID(forName: "zoom.us") == "us.zoom.xos")
        #expect(KnownApps.bundleID(forName: "Microsoft Teams") == "com.microsoft.teams2")
        #expect(KnownApps.bundleID(forName: " messages ") == "com.apple.MobileSMS")
        #expect(KnownApps.bundleID(forName: "Gmail") == nil)
    }
}
