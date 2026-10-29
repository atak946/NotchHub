import Foundation
import Testing
@testable import NotchHub

struct BadgeTextParserTests {
    @Test(arguments: [
        (nil, 0), ("", 0), ("   ", 0), ("3", 3), (" 12 ", 12), ("•", 1), ("!", 1),
        ("99+", 99), ("1,234", 1234), ("1.234", 1234), ("0", 0),
    ] as [(String?, Int)])
    func parses(text: String?, expected: Int) {
        #expect(BadgeTextParser.count(from: text) == expected)
    }

    @Test func capsAbsurdValues() {
        #expect(BadgeTextParser.count(from: "123456789012345678901234567890") == BadgeTextParser.maxCount)
        #expect(BadgeTextParser.count(from: "100000") == BadgeTextParser.maxCount)
    }

    @Test func ignoresNonASCIIDigits() {
        #expect(BadgeTextParser.count(from: "٣") == BadgeTextParser.nonNumericCount)
    }
}

struct DockBadgeNamingTests {
    @Test func bundleFileNameIsLanguageIndependent() {
        let url = URL(fileURLWithPath: "/System/Applications/Messages.app", isDirectory: true)
        #expect(AXDockBadgeReader.appName(fromBundleURL: url) == "Messages")
    }

    @MainActor
    @Test func localizedTitleAndFileNameBothMatchWatchedNames() {
        let badges = ["Mesajlar": 2, "Messages": 2, "WhatsApp": 1]
        let counts = UnreadBadgeMonitor.watchedCounts(from: badges, watched: ["Messages", "whatsapp", "Slack"])
        #expect(counts == ["Messages": 2, "whatsapp": 1, "Slack": 0])
    }
}
