import Foundation
import Testing
@testable import NotchHub

struct RemoteSessionClassifierTests {
    private func snapshot(_ source: RemoteSessionSource, _ sockets: [RemoteTCPSocket]?, pid: Int32 = 100) -> RemoteProcessSnapshot {
        RemoteProcessSnapshot(source: source, pid: pid, sockets: sockets.map { .inspected($0) } ?? .unavailable)
    }

    @Test func nothingRunningIsIdle() {
        let result = RemoteSessionClassifier.classify([])
        #expect(!result.isActive)
        #expect(!result.isDegraded)
        #expect(result.runningSources.isEmpty)
    }

    @Test func anyDeskIdleRelayConnectionIsNotASession() {
        let result = RemoteSessionClassifier.classify([snapshot(.anyDesk, [profilesTCP(remote: 6568)])])
        #expect(!result.isActive)
        #expect(result.runningSources == [.anyDesk])
    }

    @Test func anyDeskSecondConnectionIsASession() {
        let result = RemoteSessionClassifier.classify([
            snapshot(.anyDesk, [profilesTCP(remote: 6568), profilesTCP(remote: 443, address: .ipv4([51, 1, 2, 3]))]),
        ])
        #expect(result.active == [RemoteSessionDetection(source: .anyDesk, evidence: .connections(2))])
    }

    @Test func anyDeskIdleConnectionsAreJudgedPerProcess() {
        let result = RemoteSessionClassifier.classify([
            snapshot(.anyDesk, [profilesTCP(remote: 6568)], pid: 1),
            snapshot(.anyDesk, [profilesTCP(remote: 6568)], pid: 2),
        ])
        #expect(!result.isActive)
    }

    @Test func anyDeskDirectPortIsASession() {
        let result = RemoteSessionClassifier.classify([snapshot(.anyDesk, [profilesTCP(local: 7070, remote: 61_000)])])
        #expect(result.isActive)
    }

    @Test func loopbackListeningAndClosedSocketsAreIgnored() {
        let result = RemoteSessionClassifier.classify([
            snapshot(.anyDesk, [
                profilesTCP(remote: 6568),
                profilesTCP(address: .ipv4([127, 0, 0, 1])),
                profilesTCP(address: .ipv6(Array(repeating: 0, count: 15) + [1])),
                profilesTCP(.listening, local: 7070, remote: 0, address: .ipv4([0, 0, 0, 0])),
                profilesTCP(.other, remote: 8080),
            ]),
        ])
        #expect(!result.isActive)
    }

    @Test func ipv4MappedLoopbackIsLoopback() {
        let mapped: [UInt8] = Array(repeating: 0, count: 10) + [0xFF, 0xFF, 127, 0, 0, 1]
        #expect(RemoteSocketAddress.ipv6(mapped).isLoopbackOrUnspecified)
        let global: [UInt8] = [0x2A, 0x01] + Array(repeating: 0, count: 13) + [1]
        #expect(!RemoteSocketAddress.ipv6(global).isLoopbackOrUnspecified)
    }

    @Test func screenSharingWithConnectionIsASession() {
        let result = RemoteSessionClassifier.classify([snapshot(.screenSharing, [profilesTCP(local: 5900, remote: 52_000)])])
        #expect(result.active == [RemoteSessionDetection(source: .screenSharing, evidence: .connections(1))])
    }

    @Test func uninspectableScreenSharingDegradesToProcessDetection() {
        let result = RemoteSessionClassifier.classify([snapshot(.screenSharing, nil)])
        #expect(result.active == [RemoteSessionDetection(source: .screenSharing, evidence: .processOnly)])
        #expect(result.isDegraded)
        #expect(result.uninspectableSources == [.screenSharing])
    }

    @Test func uninspectableRemoteManagementIsNotASession() {
        let result = RemoteSessionClassifier.classify([snapshot(.remoteManagement, nil)])
        #expect(!result.isActive)
        #expect(result.isDegraded)
    }

    @Test func remoteManagementNeedsViewerOnVNCPort() {
        #expect(!RemoteSessionClassifier.classify([snapshot(.remoteManagement, [profilesTCP(remote: 443)])]).isActive)
        #expect(RemoteSessionClassifier.classify([snapshot(.remoteManagement, [profilesTCP(local: 5900)])]).isActive)
    }

    @Test func executablePathMapping() {
        #expect(LibprocRemoteSessionProbe.source(forExecutablePath: "/Applications/AnyDesk.app/Contents/MacOS/AnyDesk") == .anyDesk)
        #expect(LibprocRemoteSessionProbe.source(forExecutablePath: "/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd") == .screenSharing)
        #expect(LibprocRemoteSessionProbe.source(forExecutablePath: "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/MacOS/ARDAgent") == .remoteManagement)
        #expect(LibprocRemoteSessionProbe.source(forExecutablePath: "/System/Library/PrivateFrameworks/RemoteManagement.framework/XPCServices/ScreenSharingSubscriber.xpc/Contents/MacOS/ScreenSharingSubscriber") == nil)
    }

    @Test func liveProbeDoesNotCrash() {
        _ = LibprocRemoteSessionProbe().snapshots()
    }
}

struct RemoteSessionDebouncerTests {
    @Test func requiresConsecutiveReadingsToFlip() {
        var debouncer = RemoteSessionDebouncer(requiredPolls: 2)
        #expect(debouncer.feed(true) == nil)
        #expect(debouncer.feed(false) == nil)
        #expect(debouncer.feed(true) == nil)
        #expect(debouncer.feed(true) == true)
        #expect(debouncer.feed(true) == nil)
        #expect(debouncer.feed(false) == nil)
        #expect(debouncer.feed(false) == false)
        #expect(!debouncer.isActive)
    }
}

struct ProfilesVPNDetectorTests {
    private func address(_ name: String, _ family: ProfilesInterfaceAddress.Family, up: Bool = true) -> ProfilesInterfaceAddress {
        ProfilesInterfaceAddress(name: name, isUp: up, isRunning: up, family: family)
    }

    @Test func linkLocalOnlyTunnelsAreNotVPN() {
        #expect(!ProfilesVPNDetector.isTunnelUp([address("utun0", .ipv6LinkLocal), address("en0", .ipv4)]))
    }

    @Test func tunnelWithIPv4IsVPN() {
        #expect(ProfilesVPNDetector.isTunnelUp([address("utun7", .ipv4)]))
        #expect(ProfilesVPNDetector.isTunnelUp([address("utun3", .ipv6Global)]))
    }

    @Test func downTunnelIsNotVPN() {
        #expect(!ProfilesVPNDetector.isTunnelUp([address("utun7", .ipv4, up: false)]))
    }
}

@MainActor
struct RemoteSessionMonitorTests {
    private let defaults = makeProfilesTestDefaults()
    private let alerts = makeProfilesTestAlerts()
    private let probe = ProfilesFakeProbe()

    private func makeMonitor() -> (RemoteSessionMonitor, ProfilesStore) {
        let store = ProfilesStore(defaults: defaults)
        return (RemoteSessionMonitor(store: store, alerts: alerts, probe: probe), store)
    }

    private var activeAnyDesk: [RemoteProcessSnapshot] {
        [RemoteProcessSnapshot(source: .anyDesk, pid: 1, sockets: .inspected([profilesTCP(remote: 6568), profilesTCP(local: 7070)]))]
    }

    @Test func sessionStartAndEndPostAlertsAfterDebounce() async {
        let (monitor, _) = makeMonitor()
        probe.set(activeAnyDesk)
        await monitor.poll()
        #expect(!monitor.isSessionActive)
        await monitor.poll()
        #expect(monitor.isSessionActive)
        #expect(monitor.hasCompactIndicator)
        #expect(alerts.current?.style == .urgent)
        #expect(alerts.current?.title == "AnyDesk oturumu etkin")

        probe.set([])
        await monitor.poll()
        await monitor.poll()
        #expect(!monitor.isSessionActive)
        #expect(alerts.current?.style == .success)
        #expect(alerts.current?.coalescingKey == RemoteSessionMonitor.alertKey)
    }

    @Test func disabledMonitorShowsNothing() async {
        let (monitor, store) = makeMonitor()
        store.remoteMonitorEnabled = false
        probe.set(activeAnyDesk)
        await monitor.poll()
        await monitor.poll()
        #expect(!monitor.isSessionActive)
        #expect(!monitor.hasCompactIndicator)
        #expect(alerts.current == nil)
    }

    @Test func alertsCanBeMutedWhileIndicatorStays() async {
        let (monitor, store) = makeMonitor()
        store.remoteAlertsEnabled = false
        probe.set(activeAnyDesk)
        await monitor.poll()
        await monitor.poll()
        #expect(monitor.hasCompactIndicator)
        #expect(alerts.current == nil)
    }
}
