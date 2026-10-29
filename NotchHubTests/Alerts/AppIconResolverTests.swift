import AppKit
import Testing
@testable import NotchHub

@MainActor
private final class FakeLocator: AppLocating {
    var bundleURLs: [String: URL] = [:]
    var runningURLs: [String: URL] = [:]
    var installedURLs: [String: URL] = [:]
    private(set) var lookups = 0

    func applicationURL(bundleID: String) -> URL? {
        lookups += 1
        return bundleURLs[bundleID]
    }

    func runningApplicationURL(named name: String) -> URL? { runningURLs[name] }
    func installedApplicationURL(named name: String) -> URL? { installedURLs[name] }
}

@MainActor
struct AppIconResolverTests {
    private let whatsApp = URL(filePath: "/Applications/WhatsApp.app")
    private let running = URL(filePath: "/Applications/Running.app")
    private let installed = URL(filePath: "/Applications/Installed.app")

    @Test func prefersBundleIdentifier() {
        let locator = FakeLocator()
        locator.bundleURLs["net.whatsapp.WhatsApp"] = whatsApp
        locator.runningURLs["WhatsApp"] = running
        let resolver = AppIconResolver(locator: locator, loadIcon: { _ in NSImage() })

        #expect(resolver.applicationURL(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp") == whatsApp)
    }

    @Test func fallsBackToRunningThenInstalledAppByName() {
        let locator = FakeLocator()
        locator.runningURLs["Slack"] = running
        locator.installedURLs["Notion"] = installed
        let resolver = AppIconResolver(locator: locator, loadIcon: { _ in NSImage() })

        #expect(resolver.applicationURL(bundleID: "com.unknown.app", appName: "Slack") == running)
        #expect(resolver.applicationURL(bundleID: nil, appName: "Notion") == installed)
        #expect(resolver.applicationURL(bundleID: nil, appName: "Missing") == nil)
        #expect(resolver.applicationURL(bundleID: nil, appName: nil) == nil)
    }

    @Test(arguments: ["../../etc", "/Applications/Evil", "a:b", ".hidden", "   "])
    func rejectsPathLikeNames(name: String) {
        #expect(AppIconResolver.validName(name) == nil)
    }

    @Test(arguments: ["net.whatsapp.WhatsApp", "us.zoom.xos", "Cisco-Systems.Spark"])
    func acceptsBundleIdentifiers(bundleID: String) {
        #expect(AppIconResolver.validBundleID(bundleID) == bundleID)
    }

    @Test(arguments: ["", "com/evil", "com.evil app", String(repeating: "a", count: 300)])
    func rejectsInvalidBundleIdentifiers(bundleID: String) {
        #expect(AppIconResolver.validBundleID(bundleID) == nil)
    }

    @Test func cachesHitsAndMisses() {
        let locator = FakeLocator()
        locator.bundleURLs["net.whatsapp.WhatsApp"] = whatsApp
        var loads = 0
        let resolver = AppIconResolver(locator: locator, loadIcon: { _ in
            loads += 1
            return NSImage()
        })

        _ = resolver.icon(bundleID: "net.whatsapp.WhatsApp", appName: nil)
        _ = resolver.icon(bundleID: "net.whatsapp.WhatsApp", appName: nil)
        _ = resolver.icon(bundleID: "com.missing", appName: nil)
        _ = resolver.icon(bundleID: "com.missing", appName: nil)

        #expect(loads == 1)
        #expect(locator.lookups == 2)
    }
}
