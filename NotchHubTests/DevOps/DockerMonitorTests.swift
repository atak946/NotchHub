import Foundation
import Testing
@testable import NotchHub

struct DockerEventDecodingTests {
    @Test func decodesDieEventWithExitCode() throws {
        let json = """
        {"status":"die","id":"abc123def4567890","from":"nginx","Type":"container","Action":"die",\
        "Actor":{"ID":"abc123def4567890","Attributes":{"exitCode":"137","image":"nginx","name":"web"}},\
        "scope":"local","time":1700000000,"timeNano":1700000000500000000}
        """
        let event = try DockerEvent.decode(devOpsData(json))

        #expect(event.kind == .die)
        #expect(event.containerID == "abc123def4567890")
        #expect(event.containerName == "web")
        #expect(event.exitCode == 137)
        #expect(event.time == Date(timeIntervalSince1970: 1_700_000_000.5))
    }

    @Test func decodesHealthStatusAndKillSignal() throws {
        let health = try DockerEvent.decode(devOpsData("""
        {"Type":"container","Action":"health_status: unhealthy","Actor":{"ID":"c1","Attributes":{"name":"db"}},"time":1}
        """))
        let kill = try DockerEvent.decode(devOpsData("""
        {"Type":"container","Action":"kill","Actor":{"ID":"c1","Attributes":{"name":"db","signal":"15"}},"time":1}
        """))

        #expect(health.kind == .health(.unhealthy))
        #expect(kill.kind == .kill)
        #expect(kill.signal == 15)
    }

    @Test func decodesLegacyFieldsAndFallsBackToShortID() throws {
        let event = try DockerEvent.decode(devOpsData("""
        {"status":"oom","id":"0123456789abcdef0123","time":5}
        """))
        #expect(event.kind == .oom)
        #expect(event.containerName == "0123456789ab")
    }

    @Test func rejectsNonContainerEventsAndGarbage() {
        #expect(throws: DockerEvent.DecodingFailure.notAContainerEvent) {
            try DockerEvent.decode(devOpsData("{\"Type\":\"network\",\"Action\":\"connect\",\"Actor\":{\"ID\":\"n\"}}"))
        }
        #expect(throws: (any Error).self) {
            try DockerEvent.decode(devOpsData("not json"))
        }
    }

    @Test func parsesUnknownActionsAsOther() {
        #expect(DockerEventKind(action: "exec_start: sh") == .other("exec_start: sh"))
        #expect(DockerEventKind(action: "health_status: weird") == .other("health_status: weird"))
        #expect(DockerEventKind(action: "health_status: healthy") == .health(.healthy))
    }

    @Test func decodesContainerListWithHealthFromStatusAndHealthField() throws {
        let json = """
        [{"Id":"a","Names":["/web"],"State":"running","Status":"Up 3 minutes (unhealthy)"},
         {"Id":"b","Names":["/db"],"State":"running","Status":"Up 1 hour","Health":{"Status":"healthy"}},
         {"Id":"c","Names":["/job"],"State":"exited","Status":"Exited (1) 2 minutes ago"}]
        """
        let containers = try DockerContainerSummary.decodeList(devOpsData(json))
        let counts = DockerContainerCounts(containers)

        #expect(containers.map(\.name) == ["web", "db", "job"])
        #expect(containers.map(\.health) == [.unhealthy, .healthy, nil])
        #expect(counts == DockerContainerCounts(running: 2, total: 3, unhealthy: 1))
    }

    @Test func eventsPathIsPercentEncodedFilter() {
        let path = SocketDockerEngineClient.eventsPath
        #expect(path.hasPrefix("/events?filters=%7B%22type%22%3A%5B%22container%22%5D"))
        #expect(!path.contains("\""))
        #expect(path.removingPercentEncoding?.contains("\"health_status\"") == true)
    }

    @Test func requestIsValidHTTP11() {
        let request = String(decoding: UnixSocketHTTPClient.requestData(path: "/containers/json"), as: UTF8.self)
        #expect(request.hasPrefix("GET /containers/json HTTP/1.1\r\nHost: docker\r\n"))
        #expect(request.hasSuffix("\r\n\r\n"))
    }
}

struct DockerAlertPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(_ kind: DockerEventKind, id: String = "c1", name: String = "web", exit: Int? = nil, at offset: TimeInterval = 0) -> DockerEvent {
        DockerEvent(kind: kind, containerID: id, containerName: name, exitCode: exit, time: start.addingTimeInterval(offset))
    }

    @Test func nonZeroExitAlerts() {
        var policy = DockerAlertPolicy()
        #expect(policy.evaluate(event(.die, exit: 1)) == .died(name: "web", exitCode: 1))
    }

    @Test func zeroExitNeverAlerts() {
        var policy = DockerAlertPolicy(ignoreStopExits: false)
        #expect(policy.evaluate(event(.die, exit: 0)) == nil)
        #expect(policy.evaluate(event(.die)) == nil)
    }

    @Test func dockerStopExitsAreIgnoredAfterKill() {
        var policy = DockerAlertPolicy()
        #expect(policy.evaluate(event(.kill)) == nil)
        #expect(policy.evaluate(event(.die, exit: 143, at: 1)) == nil)

        #expect(policy.evaluate(event(.kill, at: 100)) == nil)
        #expect(policy.evaluate(event(.kill, at: 110)) == nil)  // SIGKILL after stop timeout
        #expect(policy.evaluate(event(.die, exit: 137, at: 110)) == nil)
    }

    @Test func stopExitWithoutKillOrTooLateStillAlerts() {
        var policy = DockerAlertPolicy()
        #expect(policy.evaluate(event(.die, exit: 143)) == .died(name: "web", exitCode: 143))

        _ = policy.evaluate(event(.kill, at: 10))
        #expect(policy.evaluate(event(.die, exit: 143, at: 10 + DockerAlertPolicy.stopWindow + 1)) == .died(name: "web", exitCode: 143))
    }

    @Test func killDoesNotHideRealCrashCodes() {
        var policy = DockerAlertPolicy()
        _ = policy.evaluate(event(.kill))
        #expect(policy.evaluate(event(.die, exit: 1, at: 1)) == .died(name: "web", exitCode: 1))
    }

    @Test func ignoringStopsCanBeDisabled() {
        var policy = DockerAlertPolicy(ignoreStopExits: false)
        _ = policy.evaluate(event(.kill))
        #expect(policy.evaluate(event(.die, exit: 143, at: 1)) == .died(name: "web", exitCode: 143))
    }

    @Test func killOnOtherContainerDoesNotSuppress() {
        var policy = DockerAlertPolicy()
        _ = policy.evaluate(event(.kill, id: "other"))
        #expect(policy.evaluate(event(.die, exit: 143, at: 1)) == .died(name: "web", exitCode: 143))
    }

    @Test func oomAlertsOnceAndSwallowsFollowingDie() {
        var policy = DockerAlertPolicy()
        #expect(policy.evaluate(event(.oom)) == .outOfMemory(name: "web"))
        #expect(policy.evaluate(event(.die, exit: 137, at: 1)) == nil)
        #expect(policy.evaluate(event(.die, exit: 137, at: 60)) == .died(name: "web", exitCode: 137))
    }

    @Test func healthAlertsOnlyOnTransitions() {
        var policy = DockerAlertPolicy()
        #expect(policy.evaluate(event(.health(.healthy))) == nil)
        #expect(policy.evaluate(event(.health(.unhealthy))) == .unhealthy(name: "web"))
        #expect(policy.evaluate(event(.health(.unhealthy), at: 30)) == nil)
        #expect(policy.evaluate(event(.health(.healthy), at: 60)) == .recovered(name: "web"))
        #expect(policy.evaluate(event(.health(.healthy), at: 90)) == nil)
    }

    @Test func seededUnhealthyContainerCanRecover() {
        var policy = DockerAlertPolicy()
        policy.seed(with: [DockerContainerSummary(id: "c1", name: "web", state: "running", health: .unhealthy)])
        #expect(policy.evaluate(event(.health(.unhealthy))) == nil)
        #expect(policy.evaluate(event(.health(.healthy))) == .recovered(name: "web"))
    }

    @Test func backoffDoublesAndCaps() {
        let delays = (1...9).map { DockerReconnectBackoff.delay(forAttempt: $0) }
        #expect(delays == [1, 2, 4, 8, 16, 32, 60, 60, 60].map { Duration.seconds($0) })
        #expect(DockerReconnectBackoff.delay(forAttempt: 0) == .seconds(1))
    }
}

struct DockerSocketLocatorTests {
    private let home = "/Users/tester"

    @Test func candidateOrderIsOrbStackDefaultDesktopColima() {
        #expect(DockerSocketLocator.candidatePaths(home: home + "/") == [
            "/Users/tester/.orbstack/run/docker.sock",
            "/var/run/docker.sock",
            "/Users/tester/.docker/run/docker.sock",
            "/Users/tester/.colima/default/docker.sock",
        ])
    }

    @Test func prefersOrbStackWhenSeveralExist() {
        let fileSystem = DevOpsFakeFileSystem(
            homeDirectoryPath: home,
            sockets: ["/var/run/docker.sock", "/Users/tester/.orbstack/run/docker.sock"]
        )
        #expect(DockerSocketLocator.resolve(fileSystem: fileSystem) == "/Users/tester/.orbstack/run/docker.sock")
    }

    @Test func fallsBackToColima() {
        let fileSystem = DevOpsFakeFileSystem(homeDirectoryPath: home, sockets: ["/Users/tester/.colima/default/docker.sock"])
        #expect(DockerSocketLocator.resolve(fileSystem: fileSystem) == "/Users/tester/.colima/default/docker.sock")
    }

    @Test func returnsNilWithoutSockets() {
        #expect(DockerSocketLocator.resolve(fileSystem: DevOpsFakeFileSystem(homeDirectoryPath: home, sockets: [])) == nil)
    }

    @Test func localFileSystemRejectsRegularFiles() throws {
        let path = NSTemporaryDirectory() + "devops-\(UUID().uuidString).txt"
        try Data("x".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(!LocalDevOpsFileSystem().isSocket(atPath: path))
        #expect(!LocalDevOpsFileSystem().isSocket(atPath: path + ".missing"))
    }
}

@MainActor
struct DockerMonitorTests {
    private let defaults = makeDevOpsTestDefaults()
    private let alerts = makeDevOpsAlertCenter()
    private let clock = DevOpsTestClock()
    private let pasteboard = DevOpsFakePasteboard()

    private func makeMonitor() -> DockerMonitor {
        DockerMonitor(
            alerts: alerts,
            defaults: defaults,
            client: DevOpsFakeDockerClient(),
            fileSystem: DevOpsFakeFileSystem(homeDirectoryPath: "/Users/tester", sockets: []),
            clock: clock,
            pasteboard: pasteboard
        )
    }

    private func event(_ kind: DockerEventKind, exit: Int? = nil) -> DockerEvent {
        DockerEvent(kind: kind, containerID: "c1", containerName: "api", exitCode: exit, time: clock.now)
    }

    @Test func diedAlertIsUrgentWithCopyLogsAction() throws {
        let monitor = makeMonitor()
        monitor.handle(event(.die, exit: 2))

        let alert = try #require(alerts.current)
        #expect(alert.style == .urgent)
        #expect(alert.title == "api sonlandı")
        #expect(alert.subtitle == "Çıkış kodu 2")
        #expect(alert.actionTitle == "Günlük komutunu kopyala")
        #expect(alert.autoDismissAfter == NotchAlert.importantDuration)

        alerts.performAction()
        #expect(pasteboard.copied == ["docker logs --tail 100 api"])
        #expect(monitor.hasCompactIndicator)
    }

    @Test func alertStylesMatchEventKinds() {
        let monitor = makeMonitor()
        monitor.handle(event(.oom))
        monitor.handle(DockerEvent(kind: .health(.unhealthy), containerID: "c2", containerName: "db", time: clock.now))
        monitor.handle(DockerEvent(kind: .health(.healthy), containerID: "c2", containerName: "db", time: clock.now))

        let styles = devOpsAllAlerts(alerts).map(\.style)
        #expect(styles == [.urgent, .success])  // unhealthy and recovered share a coalescing key
        #expect(devOpsAllAlerts(alerts).last?.title == "db düzeldi")
    }

    @Test func compactBadgeExpiresAfterWindow() {
        let monitor = makeMonitor()
        monitor.handle(event(.die, exit: 1))
        #expect(monitor.hasCompactIndicator)

        clock.advance(by: DockerMonitor.recentFailureWindow + 1)
        #expect(!monitor.hasCompactIndicator)
    }

    @Test func unhealthyContainersLightBadge() {
        let monitor = makeMonitor()
        monitor.apply(containers: [DockerContainerSummary(id: "c1", name: "api", state: "running", health: .unhealthy)])
        #expect(monitor.counts == DockerContainerCounts(running: 1, total: 1, unhealthy: 1))
        #expect(monitor.hasCompactIndicator)
    }

    @Test func alertsCanBeDisabledButBadgeStillTracks() {
        let monitor = makeMonitor()
        monitor.alertsEnabled = false
        monitor.handle(event(.die, exit: 1))
        #expect(alerts.current == nil)
        #expect(monitor.hasRecentFailure)
    }

    @Test func ignoreStopExitsSettingPersistsAndApplies() {
        let monitor = makeMonitor()
        monitor.ignoreStopExits = false
        monitor.handle(event(.kill))
        monitor.handle(event(.die, exit: 143))
        #expect(alerts.current?.subtitle == "Çıkış kodu 143")

        let reloaded = makeMonitor()
        #expect(!reloaded.ignoreStopExits)
    }

    @Test func startWithoutSocketReportsNotFound() async throws {
        let monitor = makeMonitor()
        monitor.start()
        for _ in 0..<100 where monitor.daemonState != .socketNotFound {
            await Task.yield()
        }
        #expect(monitor.daemonState == .socketNotFound)
        monitor.stop()
        #expect(monitor.daemonState == .stopped)
    }
}
