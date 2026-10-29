import Foundation
import Testing
@testable import NotchHub

@MainActor
struct CaptureCatcherServiceTests {
    private typealias P = AutomationsPaths

    private let defaults = makeAutomationsTestDefaults()
    private let clock = AutomationsTestClock()
    private let probe = AutomationsFakeProbe()
    private let watcher = AutomationsFakeWatcher()
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })

    private final class ShelfSpy {
        var added: [[URL]] = []
    }

    private let shelf = ShelfSpy()

    private func makeService(preferences: AutomationsFakePreferences = AutomationsFakePreferences()) -> CaptureCatcherService {
        let clock = clock
        let shelf = shelf
        return CaptureCatcherService(
            alerts: alerts,
            addToShelf: { shelf.added.append($0) },
            watcher: watcher,
            probe: probe,
            folders: P.resolver(preferences),
            defaults: defaults,
            now: { clock.now },
            sleep: automationsNeverSleep
        )
    }

    private func drain(_ service: CaptureCatcherService) {
        for _ in 0..<10 {
            clock.advance(by: 0.5)
            service.pump()
        }
    }

    @Test func initTouchesNothing() {
        _ = makeService()
        #expect(watcher.startedPaths.isEmpty)
    }

    @Test func startWatchesScreenshotAndDownloadFolders() {
        let service = makeService()
        service.start()
        service.start()
        #expect(watcher.startedPaths == [[P.desktop, P.downloads]])
        #expect(service.isWatching)
        #expect(service.protectedFolders == [P.desktop, P.downloads])
        service.stop()
        #expect(!service.isWatching)
        #expect(service.watchedFolders.isEmpty)
    }

    @Test func readsScreenCaptureLocationAndShottrFolder() {
        let preferences = AutomationsFakePreferences(values: [
            "com.apple.screencapture/location": "~/Pictures/Shots/",
            "cc.ffitch.shottr/defaultFolder": "file:///Users/tester/Pictures/Shottr/",
        ])
        let service = makeService(preferences: preferences)
        service.start()
        #expect(watcher.startedPaths.last == [P.shots, "/Users/tester/Pictures/Shottr", P.downloads])
        #expect(service.protectedFolders == [P.downloads])
    }

    @Test func missingOrBogusFoldersFallBack() {
        let resolver = P.resolver(AutomationsFakePreferences(values: [
            "com.apple.screencapture/location": "/nope",
            "cc.ffitch.shottr/defaultFolder": "",
        ]))
        #expect(resolver.systemScreenshotFolder == P.desktop)
        #expect(resolver.shottrFolder == nil)
        #expect(resolver.resolvedFolder("relative/path") == nil)
    }

    @Test func settingsChangesRestartTheWatcherAndPersist() {
        let service = makeService()
        service.start()
        service.watchDownloads = false
        #expect(watcher.startedPaths.last == [P.desktop])
        service.customScreenshotFolder = P.shots
        #expect(watcher.startedPaths.last == [P.desktop, P.shots])
        service.isEnabled = false
        #expect(watcher.handler == nil)

        let reloaded = makeService()
        #expect(!reloaded.isEnabled)
        #expect(!reloaded.watchDownloads)
        #expect(reloaded.customScreenshotFolder == P.shots)
    }

    @Test func burstOfDownloadsBecomesOneAlertWithAddToShelf() throws {
        let service = makeService()
        service.start()
        let names = ["a.zip", "b.pdf", "c.dmg"]
        for name in names {
            probe.put("\(P.downloads)/\(name)", size: 100, created: clock.now)
        }
        watcher.send(names.map { .created("\(P.downloads)/\($0)") })
        drain(service)

        let alert = try #require(alerts.current)
        #expect(alert.title == "3 dosya indirildi")
        #expect(alert.actionTitle == "Rafa ekle")
        #expect(alert.coalescingKey == CaptureCatcherService.alertKey)
        #expect(alerts.queue.isEmpty)
        #expect(service.canShelveLastBatch)

        alerts.performAction()
        #expect(shelf.added.count == 1)
        #expect(Set(shelf.added[0].map(\.lastPathComponent)) == Set(names))
        #expect(!service.canShelveLastBatch)
        #expect(!service.hasOutstandingWork)
    }

    @Test func autoAddsScreenshotsButOffersDownloads() throws {
        let service = makeService()
        service.autoAddScreenshots = true
        service.start()
        let shot = "\(P.desktop)/Screenshot.png"
        let zip = "\(P.downloads)/a.zip"
        probe.put(shot, size: 100, created: clock.now)
        probe.put(zip, size: 100, created: clock.now)
        watcher.send([.created(shot), .created(zip)])
        drain(service)

        #expect(shelf.added.map { $0.map(\.lastPathComponent) } == [["Screenshot.png"]])
        let alert = try #require(alerts.current)
        #expect(alert.title == "2 yeni dosya")
        alerts.performAction()
        #expect(shelf.added.last?.map(\.lastPathComponent) == ["a.zip"])
    }

    @Test func singleAutoAddedScreenshotNeedsNoAction() throws {
        let service = makeService()
        service.autoAddScreenshots = true
        service.start()
        let shot = "\(P.desktop)/Screenshot.png"
        probe.put(shot, size: 100, created: clock.now)
        watcher.send([.created(shot)])
        drain(service)

        let alert = try #require(alerts.current)
        #expect(alert.actionTitle == nil)
        #expect(alert.style == .success)
    }

    @Test func tileActionShelvesLastBatchOnce() {
        let service = makeService()
        service.start()
        let zip = "\(P.downloads)/a.zip"
        probe.put(zip, size: 100, created: clock.now)
        watcher.send([.created(zip)])
        drain(service)

        service.shelveLastBatch()
        service.shelveLastBatch()
        #expect(shelf.added.count == 1)
    }

    @Test func failedWatcherReportsNotWatching() {
        watcher.startSucceeds = false
        let service = makeService()
        service.start()
        #expect(!service.isWatching)
    }
}
