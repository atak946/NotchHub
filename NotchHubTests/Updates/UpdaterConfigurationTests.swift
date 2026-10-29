import Foundation
import Testing
@testable import NotchHub

struct UpdaterConfigurationTests {
    private static let feed = "https://github.com/owner/repo/releases/latest/download/appcast.xml"
    private static let key = "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="

    private func configuration(feed: Any? = feed, key: Any? = key) -> UpdaterConfiguration {
        var info: [String: Any] = [:]
        info[UpdaterConfiguration.feedURLKey] = feed
        info[UpdaterConfiguration.publicKeyKey] = key
        return UpdaterConfiguration(infoDictionary: info)
    }

    @Test func feedAndKeyEnableUpdates() {
        let config = configuration()

        #expect(config.isConfigured)
        #expect(config.feedURL?.absoluteString == Self.feed)
    }

    @Test(arguments: ["", "   ", "$(SU_FEED_URL)"])
    func emptyFeedDisablesUpdates(feed: String) {
        #expect(!configuration(feed: feed).isConfigured)
    }

    @Test(arguments: ["", "  \n", "$(SU_PUBLIC_ED_KEY)"])
    func emptyKeyDisablesUpdates(key: String) {
        #expect(!configuration(key: key).isConfigured)
    }

    @Test func missingKeysDisableUpdates() {
        #expect(!configuration(feed: nil).isConfigured)
        #expect(!configuration(key: nil).isConfigured)
        #expect(!UpdaterConfiguration(infoDictionary: [:]).isConfigured)
    }

    @Test(arguments: ["http://example.com/appcast.xml", "https:", "not a url", "file:///tmp/appcast.xml"])
    func insecureOrTruncatedFeedDisablesUpdates(feed: String) {
        #expect(!configuration(feed: feed).isConfigured)
    }

    @Test func nonStringValuesDisableUpdates() {
        #expect(!configuration(feed: 42, key: true).isConfigured)
    }

    @Test func versionTextCombinesMarketingAndBuild() {
        let info = ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "7"]

        #expect(AppVersion.text(infoDictionary: info) == "1.2.0 (7)")
        #expect(AppVersion.text(infoDictionary: ["CFBundleShortVersionString": "1.2.0"]) == "1.2.0")
    }
}
