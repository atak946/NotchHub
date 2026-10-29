import Foundation
import Testing
@testable import NotchHub

@MainActor
struct VPNMonitorTests {
    private let clock = SystemTestClock()
    private let reader = SystemTestVPNReader()
    private let alerts = SystemTestSupport.makeAlertCenter()

    private func makeMonitor(
        connected: Bool = true,
        installed: [VPNInstalledClient] = [],
        running: [SystemRunningApp] = []
    ) -> VPNMonitor {
        reader.setConnected(connected)
        let runningApps = SystemRunningApps(source: { running })
        runningApps.reload()
        let monitor = VPNMonitor(
            alerts: alerts,
            runningApps: runningApps,
            reader: reader,
            clock: clock,
            defaults: SystemTestSupport.makeDefaults(),
            installedClients: { installed }
        )
        monitor.start()
        return monitor
    }

    @Test func initialStateCommitsWithoutAlert() {
        let monitor = makeMonitor()

        #expect(monitor.state == .connected)
        #expect(alerts.current == nil)
        #expect(reader.isObserving)
    }

    @Test func dropAlertsOnlyAfterDebounce() {
        let monitor = makeMonitor()
        reader.setConnected(false)

        monitor.refresh()
        clock.advance(by: VPNMonitor.debounceInterval - 1)
        monitor.settle()
        #expect(monitor.state == .connected)
        #expect(alerts.current == nil)

        clock.advance(by: 1)
        monitor.settle()
        #expect(monitor.state == .disconnected)
        #expect(alerts.current?.title == "VPN bağlantısı koptu")
        #expect(alerts.current?.style == .urgent)
        #expect(alerts.current?.autoDismissAfter == NotchAlert.importantDuration)
        #expect(alerts.current?.coalescingKey == VPNMonitor.alertKey)
        #expect(monitor.hasCompactIndicator)
    }

    @Test func shortFlapDoesNotAlert() {
        let monitor = makeMonitor()
        reader.setConnected(false)
        monitor.refresh()
        clock.advance(by: 2)

        reader.setConnected(true)
        monitor.refresh()
        clock.advance(by: 10)
        monitor.settle()

        #expect(monitor.state == .connected)
        #expect(alerts.current == nil)
    }

    @Test func reconnectReplacesDropAlert() {
        let monitor = makeMonitor()
        reader.setConnected(false)
        monitor.refresh()
        clock.advance(by: VPNMonitor.debounceInterval)
        monitor.settle()

        reader.setConnected(true)
        monitor.refresh()
        clock.advance(by: VPNMonitor.debounceInterval)
        monitor.settle()

        #expect(alerts.current?.title == "VPN yeniden bağlandı")
        #expect(alerts.current?.style == .success)
        #expect(alerts.current?.autoDismissAfter != nil)
        #expect(alerts.queue.isEmpty)
        #expect(!monitor.hasCompactIndicator)
    }

    @Test func neverConnectedDoesNotAlert() {
        let monitor = makeMonitor(connected: false)
        reader.setConnected(true)
        monitor.refresh()
        clock.advance(by: VPNMonitor.debounceInterval)
        monitor.settle()

        #expect(monitor.state == .connected)
        #expect(alerts.current == nil)
    }

    @Test func alertsCanBeSwitchedOff() {
        let monitor = makeMonitor()
        monitor.alertsEnabled = false
        reader.setConnected(false)
        monitor.refresh()
        clock.advance(by: VPNMonitor.debounceInterval)
        monitor.settle()

        #expect(monitor.state == .disconnected)
        #expect(alerts.current == nil)
    }

    @Test func disablingStopsObservingAndResetsState() {
        let monitor = makeMonitor()

        monitor.isEnabled = false

        #expect(!reader.isObserving)
        #expect(monitor.state == .unknown)
    }

    // MARK: - Client detection

    private func installed(_ id: String) throws -> VPNInstalledClient {
        let client = try #require(VPNClientCatalog.client(id: id))
        return VPNInstalledClient(
            client: client,
            appURL: URL(fileURLWithPath: client.appPaths[0]),
            bundleIdentifier: client.bundleIdentifiers[0]
        )
    }

    @Test func noKnownClientShowsGenericName() {
        let monitor = makeMonitor()

        #expect(monitor.clientDisplayName == nil)
        #expect(monitor.displayName == "VPN")
        #expect(monitor.launchTarget == nil)
    }

    @Test func installedClientNamesDropAlert() throws {
        let monitor = makeMonitor(installed: [try installed("globalprotect")])
        reader.setConnected(false)
        monitor.refresh()
        clock.advance(by: VPNMonitor.debounceInterval)
        monitor.settle()

        #expect(monitor.displayName == "GlobalProtect")
        #expect(alerts.current?.subtitle == "GlobalProtect")
        #expect(alerts.current?.actionTitle == "Aç")
    }

    @Test func runningClientWinsOverFirstInstalled() throws {
        let monitor = makeMonitor(
            installed: [try installed("cisco"), try installed("tailscale")],
            running: [SystemRunningApp(bundleIdentifier: "io.tailscale.ipn.macsys", name: "Tailscale")]
        )

        #expect(monitor.runningClient?.id == "tailscale")
        #expect(monitor.isClientRunning)
        #expect(monitor.displayName == "Tailscale")
        #expect(monitor.launchTarget?.client.id == "tailscale")
    }
}
