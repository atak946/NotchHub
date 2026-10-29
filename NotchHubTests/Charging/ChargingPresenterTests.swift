import Foundation
import Testing
@testable import NotchHub

@MainActor
private final class FakePowerSource: PowerSourceMonitoring {
    var current: PowerSnapshot?
    private(set) var onChange: (@MainActor () -> Void)?

    init(_ current: PowerSnapshot?) { self.current = current }

    func snapshot() -> PowerSnapshot? { current }
    func startObserving(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func stopObserving() { onChange = nil }

    func emit(_ snapshot: PowerSnapshot?) {
        current = snapshot
        onChange?()
    }
}

@MainActor
struct ChargingPresenterTests {
    private static let onBattery = PowerSnapshot(percent: 62, isPluggedIn: false, isCharging: false)
    private static let charging = PowerSnapshot(percent: 62, isPluggedIn: true, isCharging: true, minutesToFull: 80)

    private let alerts = SystemTestSupport.makeAlertCenter()
    private let defaults = SystemTestSupport.makeDefaults()

    private func makePresenter(_ source: FakePowerSource) -> ChargingPresenter {
        ChargingPresenter(alerts: alerts, source: source, defaults: defaults, sleep: { _ in })
    }

    private func emit(_ snapshot: PowerSnapshot?, on source: FakePowerSource, presenter: ChargingPresenter) async {
        source.emit(snapshot)
        await presenter.pendingEvaluation?.value
    }

    @Test func togglesDefaultOnAndPersist() {
        let presenter = makePresenter(FakePowerSource(nil))
        #expect(presenter.showsCharging)
        #expect(presenter.warnsLowBattery)
        presenter.showsCharging = false
        #expect(defaults.object(forKey: ChargingPresenter.Keys.showsCharging) as? Bool == false)
        #expect(!makePresenter(FakePowerSource(nil)).showsCharging)
    }

    @Test func plugInPostsChargingAlert() async {
        let source = FakePowerSource(Self.onBattery)
        let presenter = makePresenter(source)
        presenter.start()
        #expect(alerts.current == nil)

        await emit(Self.charging, on: source, presenter: presenter)

        let alert = alerts.current
        #expect(alert?.coalescingKey == ChargingPresenter.alertKey)
        #expect(alert?.battery?.state == .charging)
        #expect(alert?.autoDismissAfter == ChargingAlertContent.presentationDuration)
    }

    @Test func settleCoalescesNegotiationUpdates() async {
        let source = FakePowerSource(Self.onBattery)
        let presenter = ChargingPresenter(
            alerts: alerts, source: source, defaults: defaults,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        presenter.start()
        source.emit(PowerSnapshot(percent: 62, isPluggedIn: true, isCharging: false))
        source.emit(Self.onBattery)
        // Net change is none: the pending evaluation is replaced and never presents a plug-in.
        #expect(presenter.pendingEvaluation != nil)
        #expect(alerts.current == nil)
        presenter.stop()
        #expect(presenter.pendingEvaluation == nil)
    }

    @Test func desktopWithoutBatteryShowsNothing() async {
        let source = FakePowerSource(nil)
        let presenter = makePresenter(source)
        presenter.start()
        await emit(nil, on: source, presenter: presenter)
        #expect(!presenter.hasBattery)
        #expect(alerts.current == nil)
    }

    @Test func blockedPostingShowsNothing() async {
        let source = FakePowerSource(Self.onBattery)
        let presenter = makePresenter(source)
        presenter.canPostAlert = { false }
        presenter.start()
        await emit(Self.charging, on: source, presenter: presenter)
        #expect(alerts.current == nil)
    }

    @Test func plugInNeverQueuesBehindAnotherAlert() async {
        let source = FakePowerSource(Self.onBattery)
        let presenter = makePresenter(source)
        presenter.start()
        alerts.post(NotchAlert(module: nil, systemImage: "bell", title: "Other"))
        await emit(Self.charging, on: source, presenter: presenter)
        #expect(alerts.current?.title == "Other")
        #expect(alerts.queue.isEmpty)
    }

    @Test func lowBatteryQueuesBehindAnotherAlert() async {
        let source = FakePowerSource(PowerSnapshot(percent: 21, isPluggedIn: false, isCharging: false))
        let presenter = makePresenter(source)
        presenter.start()
        alerts.post(NotchAlert(module: nil, systemImage: "bell", title: "Other"))
        await emit(PowerSnapshot(percent: 20, isPluggedIn: false, isCharging: false), on: source, presenter: presenter)
        #expect(alerts.queue.first?.battery?.state == .low)
    }

    @Test func bothTogglesOffStopObserving() {
        let source = FakePowerSource(Self.onBattery)
        let presenter = makePresenter(source)
        presenter.start()
        #expect(source.onChange != nil)
        presenter.showsCharging = false
        presenter.warnsLowBattery = false
        #expect(source.onChange == nil)
        #expect(!presenter.isMonitoring)
    }

    @Test func reEnablingTakesAFreshBaseline() async {
        let source = FakePowerSource(Self.onBattery)
        let presenter = makePresenter(source)
        presenter.start()
        presenter.stop()
        source.current = Self.charging
        presenter.start()
        #expect(alerts.current == nil)
    }
}
