import Foundation
import Testing
@testable import NotchHub

@MainActor
struct FocusGuardServiceTests {
    private let defaults = makeAutomationsTestDefaults()
    private let clock = AutomationsTestClock()
    private let workspace = AutomationsFakeWorkspace()
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let editor = FocusActivation(bundleID: "com.microsoft.VSCode", name: "Code", processID: 11)
    private let whatsApp = FocusActivation(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", processID: 22)
    private let discord = FocusActivation(bundleID: "com.hnc.Discord", name: "Discord", processID: 33)

    /// Snapshot returned to the service; tests mutate it to simulate the timer.
    private final class TimerBox {
        var snapshot = FocusTimerSnapshot(state: .running(.work), remaining: 1200, phaseDuration: 1500)
    }

    private let timer = TimerBox()

    private func makeService() -> FocusGuardService {
        let clock = clock
        let timer = timer
        return FocusGuardService(
            alerts: alerts,
            timerSnapshot: { timer.snapshot },
            workspace: workspace,
            defaults: defaults,
            now: { clock.now },
            ownBundleID: "com.example.NotchHub"
        )
    }

    @Test func initDoesNotObserve() {
        _ = makeService()
        #expect(workspace.startCount == 0)
    }

    @Test func startAndStopAreIdempotent() {
        let service = makeService()
        service.start()
        service.start()
        #expect(workspace.startCount == 1)
        service.stop()
        service.stop()
        #expect(workspace.stopCount == 1)
        #expect(!workspace.isObserving)
    }

    @Test func disablingStopsObserving() {
        let service = makeService()
        service.start()
        service.isEnabled = false
        #expect(!workspace.isObserving)
        service.isEnabled = true
        #expect(workspace.isObserving)
    }

    @Test func remindsAndReturnsToPreviousApp() throws {
        let service = makeService()
        service.start()
        workspace.send(editor)
        workspace.send(whatsApp)

        let alert = try #require(alerts.current)
        #expect(alert.title == "Odak zamanı — 20 dk kaldı")
        #expect(alert.style == .reminder)
        #expect(alert.actionTitle == "İşe dön")
        #expect(alert.coalescingKey == FocusGuardService.alertKey)
        #expect(service.distractionsToday == 1)

        alerts.performAction()
        #expect(workspace.activatedPIDs == [11])
    }

    @Test func frontmostAppAtStartIsTheReturnTarget() {
        workspace.frontmostApp = editor
        let service = makeService()
        service.start()
        workspace.send(whatsApp)
        alerts.performAction()
        #expect(workspace.activatedPIDs == [11])
    }

    @Test func noActionWithoutAKnownPreviousApp() {
        let service = makeService()
        service.start()
        workspace.send(whatsApp)
        #expect(alerts.current?.actionTitle == nil)
    }

    @Test func cooldownSuppressesRepeatAlertsButStillCounts() {
        let service = makeService()
        service.start()
        workspace.send(editor)
        workspace.send(whatsApp)
        alerts.dismiss()

        clock.advance(by: 30)
        workspace.send(editor)
        workspace.send(whatsApp)
        #expect(alerts.current == nil)
        #expect(service.distractionsToday == 2)

        workspace.send(discord)
        #expect(alerts.current != nil)
        alerts.dismiss()

        clock.advance(by: 120)
        workspace.send(whatsApp)
        #expect(alerts.current != nil)
        #expect(service.distractionsToday == 4)
    }

    @Test func customCooldownApplies() {
        let service = makeService()
        service.cooldown = 30
        service.start()
        workspace.send(whatsApp)
        alerts.dismiss()
        clock.advance(by: 31)
        workspace.send(whatsApp)
        #expect(alerts.current != nil)
    }

    @Test func ignoresBreaksGraceAndOwnApp() {
        let service = makeService()
        service.start()

        timer.snapshot = FocusTimerSnapshot(state: .running(.shortBreak), remaining: 200, phaseDuration: 300)
        workspace.send(whatsApp)
        timer.snapshot = FocusTimerSnapshot(state: .running(.work), remaining: 1495, phaseDuration: 1500)
        workspace.send(whatsApp)
        #expect(alerts.current == nil)
        #expect(service.distractionsToday == 0)

        workspace.send(editor)
        workspace.send(FocusActivation(bundleID: "com.example.NotchHub", name: "NotchHub", processID: 1))
        timer.snapshot = FocusTimerSnapshot(state: .running(.work), remaining: 1000, phaseDuration: 1500)
        workspace.send(whatsApp)
        alerts.performAction()
        #expect(workspace.activatedPIDs == [11])
    }

    @Test func disabledListEntryIsIgnored() {
        let service = makeService()
        service.setApp("net.whatsapp.whatsapp", enabled: false)
        service.start()
        workspace.send(whatsApp)
        #expect(alerts.current == nil)
    }

    @Test func listCooldownAndCountPersist() {
        let first = makeService()
        first.addApp(FocusApp(bundleID: "com.apple.Safari", name: "Safari"))
        first.removeApp("com.hnc.discord")
        first.cooldown = 300
        first.isEnabled = false
        first.isEnabled = true
        first.start()
        workspace.send(whatsApp)

        let second = makeService()
        #expect(second.apps.contains { $0.bundleID == "com.apple.Safari" })
        #expect(!second.apps.contains { $0.bundleID == "com.hnc.Discord" })
        #expect(second.cooldown == 300)
        #expect(second.distractionsToday == 1)

        second.resetApps()
        #expect(makeService().apps == FocusApp.defaults)
    }

    @Test func automationsFacadeReadsRealTimer() {
        let shelfDefaults = makeAutomationsTestDefaults()
        let timerClock = FakeTimerClock()
        let timerService = TimerService(defaults: shelfDefaults, clock: timerClock, notifier: FakeTimerNotifier())
        let shelf = ShelfStore(defaults: shelfDefaults, storageDirectory: FileManager.default.temporaryDirectory
            .appending(path: "AutomationsShelf-\(UUID().uuidString)"))
        let watcher = AutomationsFakeWatcher()
        let automations = Automations(
            alerts: alerts, timer: timerService, shelf: shelf, defaults: defaults,
            workspace: workspace, watcher: watcher, probe: AutomationsFakeProbe(), folders: AutomationsPaths.resolver()
        )
        automations.start()
        #expect(workspace.isObserving)
        #expect(watcher.startedPaths.count == 1)

        timerService.startPomodoro()
        workspace.send(whatsApp)
        #expect(alerts.current == nil) // grace period

        timerClock.advance(by: 60)
        timerService.refresh()
        workspace.send(whatsApp)
        #expect(alerts.current?.title == "Odak zamanı — 24 dk kaldı")

        automations.stop()
        #expect(!workspace.isObserving)
        timerService.cancel()
    }
}
