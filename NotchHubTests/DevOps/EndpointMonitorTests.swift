import Foundation
import Security
import Testing
@testable import NotchHub

struct EndpointHealthMachineTests {
    @Test func firstSuccessGoesUpWithoutTransition() {
        var machine = EndpointHealthMachine()
        #expect(machine.record(.success(latency: 0.1)) == nil)
        #expect(machine.state == .up)
    }

    @Test func downRequiresTwoConsecutiveFailures() {
        var machine = EndpointHealthMachine()
        _ = machine.record(.success(latency: 0.1))

        #expect(machine.record(.failure(reason: "Timed out")) == nil)
        #expect(machine.state == .degraded)
        #expect(machine.record(.failure(reason: "Timed out")) == .wentDown(reason: "Timed out"))
        #expect(machine.state == .down)
        #expect(machine.record(.failure(reason: "Timed out")) == nil)
        #expect(machine.state == .down)
    }

    @Test func singleBlipDoesNotAlert() {
        var machine = EndpointHealthMachine()
        _ = machine.record(.success(latency: 0.1))
        _ = machine.record(.failure(reason: "x"))
        #expect(machine.record(.success(latency: 0.1)) == nil)
        #expect(machine.state == .up)
        #expect(machine.consecutiveFailures == 0)
    }

    @Test func recoveryFromDownTransitions() {
        var machine = EndpointHealthMachine()
        _ = machine.record(.failure(reason: "x"))
        #expect(machine.state == .unknown)
        #expect(machine.record(.failure(reason: "x")) == .wentDown(reason: "x"))
        #expect(machine.record(.success(latency: 0.2)) == .recovered)
        #expect(machine.state == .up)
    }

    @Test func slowSuccessIsDegraded() {
        var machine = EndpointHealthMachine()
        _ = machine.record(.success(latency: EndpointHealthMachine.slowLatencyThreshold + 0.5))
        #expect(machine.state == .degraded)
    }

    @Test func vpnPauseResetsFailuresWithoutAlert() {
        var machine = EndpointHealthMachine()
        _ = machine.record(.success(latency: 0.1))
        _ = machine.record(.failure(reason: "x"))

        #expect(machine.record(.vpnUnavailable) == nil)
        #expect(machine.state == .pausedVPNOff)
        #expect(machine.consecutiveFailures == 0)
        // After VPN returns a single failure must not confirm down.
        #expect(machine.record(.failure(reason: "x")) == nil)
        #expect(machine.state == .unknown)
    }

    @Test func classifiesProbeResults() {
        let expected = 200...299
        #expect(EndpointCheckOutcome.classify(EndpointProbeResult(statusCode: 204, latency: 0.3), expected: expected) == .success(latency: 0.3))
        #expect(EndpointCheckOutcome.classify(EndpointProbeResult(statusCode: 503), expected: expected) == .failure(reason: "HTTP 503"))
        #expect(EndpointCheckOutcome.classify(EndpointProbeResult(errorDescription: "Timed out"), expected: expected) == .failure(reason: "Timed out"))
        #expect(EndpointCheckOutcome.classify(EndpointProbeResult(), expected: expected) == .failure(reason: "Yanıt yok"))
    }
}

struct CertificateExpiryWarningPolicyTests {
    private let id = UUID()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        DateComponents(calendar: calendar, year: 2026, month: 3, day: day, hour: hour).date ?? .distantPast
    }

    @Test func doesNotWarnOutsideLeadTime() {
        var policy = CertificateExpiryWarningPolicy()
        let decision1 = !policy.shouldWarn(endpointID: id, expiry: date(30), now: date(1), calendar: calendar)
        #expect(decision1)
    }

    @Test func warnsOncePerDay() {
        var policy = CertificateExpiryWarningPolicy()
        let expiry = date(20)

        let decision2 = policy.shouldWarn(endpointID: id, expiry: expiry, now: date(10, hour: 8), calendar: calendar)
        #expect(decision2)
        let decision3 = !policy.shouldWarn(endpointID: id, expiry: expiry, now: date(10, hour: 9), calendar: calendar)
        #expect(decision3)
        let decision4 = !policy.shouldWarn(endpointID: id, expiry: expiry, now: date(10, hour: 23), calendar: calendar)
        #expect(decision4)
        let decision5 = policy.shouldWarn(endpointID: id, expiry: expiry, now: date(11, hour: 0), calendar: calendar)
        #expect(decision5)
    }

    @Test func dedupeIsPerEndpoint() {
        var policy = CertificateExpiryWarningPolicy()
        let decision6 = policy.shouldWarn(endpointID: id, expiry: date(12), now: date(10), calendar: calendar)
        #expect(decision6)
        let decision7 = policy.shouldWarn(endpointID: UUID(), expiry: date(12), now: date(10), calendar: calendar)
        #expect(decision7)
    }

    @Test func expiredCertificateStillWarns() {
        var policy = CertificateExpiryWarningPolicy()
        let decision8 = policy.shouldWarn(endpointID: id, expiry: date(1), now: date(5), calendar: calendar)
        #expect(decision8)
    }

    @Test func daysRemainingUsesCalendarDays() {
        #expect(CertificateExpiryWarningPolicy.daysRemaining(until: date(14, hour: 1), now: date(10, hour: 23), calendar: calendar) == 4)
    }

    /// Self-signed P-256 certificate with notAfter = 2030-01-01T00:00:00Z.
    private static let certificateBase64 = """
    MIIBZDCCAQqgAwIBAgIUWVfbtjugZZdF8KPGi4AIIPu1HFYwCgYIKoZIzj0EAwIwGDEWMBQGA1UEAwwNbm90Y2hodWIudGVzdDAeFw0yNjAxMDEwMDAwMDBaFw0zMDAxMDEwMDAwMDBaMBgxFjAUBgNVBAMMDW5vdGNoaHViLnRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQNg5BAiisnDkWRqs2V60eZzimvjmE2VUAGCoKA0nGpExdzMs8yV9WSQ9QE/vRg2X7MuhrmzLWUrpmkkBN5mR+vozIwMDAdBgNVHQ4EFgQUxEPyyT9Qav2clM8CTLoShSu/mF4wDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiEAy9R3LX0NqOPPLrz2UKH77A1hdIPeuoc6e8Y5OdsrehYCICRRUf76ILSnhGL1ahf+5PGnDwfcm1R3YlKXz7vvtPsC
    """

    @Test func readsNotValidAfterFromRealCertificate() throws {
        let der = try #require(Data(base64Encoded: Self.certificateBase64))
        let certificate = try #require(CertificateExpiryReader.certificate(fromDER: der))
        let expiry = try #require(CertificateExpiryReader.notValidAfter(of: certificate))

        #expect(expiry == Date(timeIntervalSince1970: 1_893_456_000))
    }
}

struct EndpointValidatorTests {
    private func endpoint(name: String = "API", url: String = "https://api.example.com/health", interval: Int = 60, lower: Int = 200, upper: Int = 299) -> MonitoredEndpoint {
        MonitoredEndpoint(name: name, url: url, intervalSeconds: interval, expectedStatusLower: lower, expectedStatusUpper: upper)
    }

    @Test func acceptsHTTPAndHTTPS() {
        #expect(EndpointValidator.isValid(endpoint()))
        #expect(EndpointValidator.isValid(endpoint(url: "http://localhost:8080/health")))
        #expect(EndpointValidator.isValid(endpoint(url: "  HTTPS://Example.com  ")))
    }

    @Test func rejectsOtherSchemes() {
        #expect(EndpointValidator.validate(endpoint(url: "ftp://example.com")) == [.unsupportedScheme])
        #expect(EndpointValidator.validate(endpoint(url: "file:///etc/hosts")) == [.unsupportedScheme])
    }

    @Test func rejectsMalformedURLs() {
        #expect(EndpointValidator.validate(endpoint(url: "")) == [.invalidURL])
        #expect(EndpointValidator.validate(endpoint(url: "example.com")) == [.invalidURL])
        #expect(EndpointValidator.validate(endpoint(url: "https://exa mple.com")) == [.invalidURL])
        #expect(EndpointValidator.validate(endpoint(url: "https://")) == [.missingHost])
    }

    @Test func rejectsBadNameIntervalAndStatusRange() {
        #expect(EndpointValidator.validate(endpoint(name: "  ")) == [.emptyName])
        #expect(EndpointValidator.validate(endpoint(interval: 29)) == [.intervalOutOfRange])
        #expect(EndpointValidator.validate(endpoint(interval: 601)) == [.intervalOutOfRange])
        #expect(EndpointValidator.validate(endpoint(lower: 300, upper: 200)) == [.invalidStatusRange])
        #expect(EndpointValidator.validate(endpoint(lower: 99)) == [.invalidStatusRange])
        #expect(EndpointValidator.isValid(endpoint(interval: 30)))
        #expect(EndpointValidator.isValid(endpoint(interval: 600)))
    }

    @Test func vpnHeuristicIgnoresSystemTunnels() {
        let system = [
            DevOpsInterfaceAddress(name: "utun0", isUp: true, family: .ipv6(isLinkLocal: true)),
            DevOpsInterfaceAddress(name: "en0", isUp: true, family: .ipv4),
        ]
        #expect(!VPNInterfaceHeuristic.isVPNActive(system))
        #expect(VPNInterfaceHeuristic.isVPNActive(system + [DevOpsInterfaceAddress(name: "utun5", isUp: true, family: .ipv4)]))
        #expect(VPNInterfaceHeuristic.isVPNActive([DevOpsInterfaceAddress(name: "ipsec0", isUp: true, family: .ipv6(isLinkLocal: false))]))
        #expect(!VPNInterfaceHeuristic.isVPNActive([DevOpsInterfaceAddress(name: "utun5", isUp: false, family: .ipv4)]))
    }
}

@MainActor
struct EndpointMonitorTests {
    private let defaults = makeDevOpsTestDefaults()
    private let alerts = makeDevOpsAlertCenter()
    private let clock = DevOpsTestClock()
    private let prober = DevOpsFakeProber()
    private let vpn = DevOpsFakeVPN(active: true)

    private func makeMonitor() -> EndpointMonitor {
        EndpointMonitor(alerts: alerts, defaults: defaults, prober: prober, vpn: vpn, clock: clock, calendar: Calendar(identifier: .gregorian))
    }

    private func addEndpoint(_ monitor: EndpointMonitor, requiresVPN: Bool = false) -> MonitoredEndpoint {
        let endpoint = MonitoredEndpoint(name: "Staging", url: "https://staging.example.com/health", requiresVPN: requiresVPN)
        #expect(monitor.add(endpoint).isEmpty)
        return endpoint
    }

    @Test func persistsEndpointsAsJSON() {
        let monitor = makeMonitor()
        let endpoint = addEndpoint(monitor)

        #expect(makeMonitor().endpoints == [endpoint])

        var edited = endpoint
        edited.name = "Prod"
        #expect(monitor.update(edited).isEmpty)
        #expect(makeMonitor().endpoints.map(\.name) == ["Prod"])

        monitor.remove(id: endpoint.id)
        #expect(makeMonitor().endpoints.isEmpty)
    }

    @Test func invalidEndpointIsNotAdded() {
        let monitor = makeMonitor()
        let errors = monitor.add(MonitoredEndpoint(name: "Bad", url: "ftp://x"))
        #expect(errors == [.unsupportedScheme])
        #expect(monitor.endpoints.isEmpty)
    }

    @Test func confirmedDownPostsUrgentThenRecoveryPostsSuccess() async {
        let monitor = makeMonitor()
        let endpoint = addEndpoint(monitor)
        prober.enqueue(
            EndpointProbeResult(statusCode: 200, latency: 0.1),
            EndpointProbeResult(errorDescription: "Timed out"),
            EndpointProbeResult(statusCode: 502, latency: 0.1),
            EndpointProbeResult(statusCode: 200, latency: 0.1)
        )

        await monitor.check(endpoint.id)
        await monitor.check(endpoint.id)
        #expect(alerts.current == nil)
        #expect(monitor.status(for: endpoint.id).state == .degraded)

        await monitor.check(endpoint.id)
        #expect(monitor.status(for: endpoint.id).state == .down)
        #expect(alerts.current?.style == .urgent)
        #expect(alerts.current?.subtitle == "HTTP 502")
        #expect(monitor.hasCompactIndicator)

        await monitor.check(endpoint.id)
        #expect(alerts.current?.style == .success)
        #expect(alerts.queue.isEmpty)  // recovery replaced the down alert
        #expect(!monitor.hasCompactIndicator)
    }

    @Test func requiresVPNPausesInsteadOfGoingDown() async {
        let monitor = makeMonitor()
        let endpoint = addEndpoint(monitor, requiresVPN: true)
        vpn.setActive(false)

        await monitor.check(endpoint.id)
        await monitor.check(endpoint.id)
        await monitor.check(endpoint.id)

        #expect(monitor.status(for: endpoint.id).state == .pausedVPNOff)
        #expect(prober.probeCount == 0)
        #expect(alerts.current == nil)

        vpn.setActive(true)
        await monitor.check(endpoint.id)
        #expect(monitor.status(for: endpoint.id).state == .up)
        #expect(alerts.current == nil)
    }

    @Test func certificateWarningIsDedupedPerDayWithInjectedClock() async {
        let monitor = makeMonitor()
        let endpoint = addEndpoint(monitor)
        let expiry = clock.now.addingTimeInterval(5 * 24 * 3600)
        prober.enqueue(
            EndpointProbeResult(statusCode: 200, latency: 0.1, certificateExpiry: expiry),
            EndpointProbeResult(statusCode: 200, latency: 0.1, certificateExpiry: expiry),
            EndpointProbeResult(statusCode: 200, latency: 0.1, certificateExpiry: expiry)
        )

        await monitor.check(endpoint.id)
        #expect(alerts.current?.style == .reminder)
        #expect(alerts.current?.subtitle?.hasPrefix("Sertifika bitişine") == true)
        alerts.dismissAll()

        clock.advance(by: 60)
        await monitor.check(endpoint.id)
        #expect(alerts.current == nil)

        clock.advance(by: 24 * 3600)
        await monitor.check(endpoint.id)
        #expect(alerts.current?.style == .reminder)
        #expect(monitor.status(for: endpoint.id).certificateExpiry == expiry)
    }

    @Test func certificateDedupeSurvivesRelaunch() async {
        let monitor = makeMonitor()
        let endpoint = addEndpoint(monitor)
        let expiry = clock.now.addingTimeInterval(24 * 3600)
        prober.enqueue(EndpointProbeResult(statusCode: 200, latency: 0.1, certificateExpiry: expiry))
        await monitor.check(endpoint.id)
        alerts.dismissAll()

        let relaunched = makeMonitor()
        prober.enqueue(EndpointProbeResult(statusCode: 200, latency: 0.1, certificateExpiry: expiry))
        await relaunched.check(endpoint.id)
        #expect(alerts.current == nil)
    }

    @Test func disabledAlertsStillTrackState() async {
        let monitor = makeMonitor()
        monitor.alertsEnabled = false
        let endpoint = addEndpoint(monitor)
        prober.enqueue(EndpointProbeResult(errorDescription: "x"), EndpointProbeResult(errorDescription: "x"))

        await monitor.check(endpoint.id)
        await monitor.check(endpoint.id)

        #expect(monitor.status(for: endpoint.id).state == .down)
        #expect(alerts.current == nil)
        #expect(monitor.overallState == .down)
    }
}
