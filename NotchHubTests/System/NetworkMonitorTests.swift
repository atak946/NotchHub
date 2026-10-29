import Foundation
import Testing
@testable import NotchHub

struct NetworkClassificationTests {
    @Test func physicalInterfaceWinsOverTunnel() {
        #expect(NetworkClassifier.primaryKind(of: [.other, .wifi], isSatisfied: true) == .wifi)
        #expect(NetworkClassifier.primaryKind(of: [.ethernet, .wifi], isSatisfied: true) == .ethernet)
        #expect(NetworkClassifier.primaryKind(of: [.other], isSatisfied: true) == .other)
        #expect(NetworkClassifier.primaryKind(of: [.loopback], isSatisfied: true) == .loopback)
        #expect(NetworkClassifier.primaryKind(of: [], isSatisfied: true) == .none)
    }

    @Test func unsatisfiedPathHasNoInterface() {
        #expect(NetworkClassifier.primaryKind(of: [.wifi], isSatisfied: false) == .none)
    }

    @Test func displayNamePrefersSSIDOnWiFi() {
        #expect(NetworkSnapshot(isOnline: true, interface: .wifi, ssid: "Office").displayName == "Office")
        #expect(NetworkSnapshot(isOnline: true, interface: .wifi).displayName == "Wi-Fi")
        #expect(NetworkSnapshot(isOnline: true, interface: .ethernet, ssid: "x").displayName == "Ethernet")
        #expect(NetworkSnapshot.offline.displayName == "Çevrimdışı")
    }

    @Test func policyEvents() {
        let wifi = NetworkSnapshot(isOnline: true, interface: .wifi, ssid: "Home")
        let office = NetworkSnapshot(isOnline: true, interface: .wifi, ssid: "Office")
        let wired = NetworkSnapshot(isOnline: true, interface: .ethernet)
        let expensive = NetworkSnapshot(isOnline: true, interface: .wifi, isExpensive: true, ssid: "Home")

        #expect(NetworkAlertPolicy.event(from: nil, to: .offline) == nil)
        #expect(NetworkAlertPolicy.event(from: wifi, to: .offline) == .wentOffline)
        #expect(NetworkAlertPolicy.event(from: .offline, to: wifi) == .backOnline(wifi))
        #expect(NetworkAlertPolicy.event(from: wifi, to: office) == .changed(office))
        #expect(NetworkAlertPolicy.event(from: wifi, to: wired) == .changed(wired))
        #expect(NetworkAlertPolicy.event(from: wifi, to: expensive) == nil)
        #expect(NetworkAlertPolicy.event(from: NetworkSnapshot.offline, to: .offline) == nil)
    }
}

@MainActor
struct NetworkMonitorTests {
    private let clock = SystemTestClock()
    private let reader = SystemTestNetworkReader()
    private let alerts = SystemTestSupport.makeAlertCenter()
    private let home = NetworkSnapshot(isOnline: true, interface: .wifi, ssid: "Home")

    private func makeMonitor() -> NetworkMonitor {
        let monitor = NetworkMonitor(alerts: alerts, reader: reader, clock: clock, defaults: SystemTestSupport.makeDefaults())
        monitor.start()
        reader.onUpdate?(home)
        return monitor
    }

    private func hold(_ monitor: NetworkMonitor) {
        clock.advance(by: NetworkMonitor.debounceInterval)
        monitor.settle()
    }

    @Test func baselineDoesNotAlert() {
        let monitor = makeMonitor()

        #expect(monitor.snapshot == home)
        #expect(alerts.current == nil)
    }

    @Test func offlineAlertStaysUntilBackOnline() {
        let monitor = makeMonitor()

        reader.onUpdate?(.offline)
        #expect(alerts.current == nil)
        hold(monitor)

        #expect(alerts.current?.title == "Çevrimdışısın")
        #expect(alerts.current?.style == .urgent)
        #expect(alerts.current?.autoDismissAfter == NotchAlert.importantDuration)
        #expect(monitor.hasCompactIndicator)

        reader.onUpdate?(home)
        hold(monitor)

        #expect(alerts.current?.title == "Tekrar çevrimiçi")
        #expect(alerts.current?.style == .success)
        #expect(alerts.queue.isEmpty)
        #expect(!monitor.hasCompactIndicator)
    }

    @Test func flappingDoesNotAlert() {
        let monitor = makeMonitor()

        for _ in 0..<5 {
            reader.onUpdate?(.offline)
            clock.advance(by: 1)
            monitor.settle()
            reader.onUpdate?(home)
            clock.advance(by: 1)
            monitor.settle()
        }

        #expect(alerts.current == nil)
        #expect(monitor.snapshot == home)
    }

    @Test func networkChangePostsShortInfoAlert() {
        let monitor = makeMonitor()
        let office = NetworkSnapshot(isOnline: true, interface: .wifi, ssid: "Office")

        reader.onUpdate?(office)
        hold(monitor)

        #expect(alerts.current?.title == "Ağ değişti")
        #expect(alerts.current?.subtitle == "Şu an: Office")
        #expect(alerts.current?.style == .info)
        #expect(alerts.current?.autoDismissAfter == NetworkMonitor.changedAlertDuration)
    }

    @Test func changeAlertsCanBeSwitchedOff() {
        let monitor = makeMonitor()
        monitor.changeAlertsEnabled = false

        reader.onUpdate?(NetworkSnapshot(isOnline: true, interface: .ethernet))
        hold(monitor)

        #expect(monitor.snapshot?.interface == .ethernet)
        #expect(alerts.current == nil)
    }

    @Test func disablingStopsReader() {
        let monitor = makeMonitor()

        monitor.isEnabled = false

        #expect(reader.onUpdate == nil)
        #expect(monitor.snapshot == nil)
    }
}
