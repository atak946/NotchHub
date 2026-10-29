import Foundation
import Testing
@testable import NotchHub

/// `notchhub://` URLs can be opened by any app or web page, so they are labelled, limited and can be switched off.
@MainActor
struct IntegrationsURLHardeningTests {
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let defaults = makeIntegrationsTestDefaults()
    private let system = IntegrationsFakeSystem()
    private let server = IntegrationsFakeSocketServer()
    private let clock = IntegrationsTestClock()
    /// Slow enough for the shared 10/10 s bucket to keep up, fast enough for the 10/min URL bucket to run dry.
    private let requestSpacing: TimeInterval = 0.5

    private func makeService() -> ExternalAlertService {
        let clock = clock
        return ExternalAlertService(
            alerts: alerts,
            defaults: defaults,
            socketServer: server,
            system: system,
            socketPath: "/tmp/notchhub-test.sock",
            calendar: integrationsUTCCalendar,
            now: { clock.now }
        )
    }

    /// Spreads requests so only the per-URL bucket (not the shared burst bucket) can run dry.
    private func sendURLAlerts(_ count: Int, to service: ExternalAlertService) -> [Bool] {
        (0..<count).map { index in
            clock.advance(by: requestSpacing)
            return service.handle(url: integrationsURL("notchhub://alert?title=u\(index)"))
        }
    }

    @Test func urlAlertsAreMarkedExternal() throws {
        let service = makeService()
        service.handle(url: integrationsURL("notchhub://alert?title=Deploy"))
        let alert = try #require(alerts.current)
        #expect(alert.appName == ExternalAlertService.externalSourceLabel)
        #expect(alert.sourceLabel == "Harici")
    }

    @Test func socketAlertsAreNotMarkedExternal() throws {
        let service = makeService()
        _ = service.handle(jsonLine: #"{"title":"Build"}"#)
        let alert = try #require(alerts.current)
        #expect(alert.appName == nil)
    }

    @Test func urlAlertsAllowedByDefault() {
        let service = makeService()
        #expect(service.urlAlertsEnabled)
    }

    @Test func disablingURLAlertsRejectsURLButKeepsSocket() {
        let service = makeService()
        service.urlAlertsEnabled = false

        #expect(!service.handle(url: integrationsURL("notchhub://alert?title=Web")))
        #expect(alerts.current == nil)
        #expect(service.handle(jsonLine: #"{"title":"CLI"}"#).contains(#""ok":true"#))
        #expect(alerts.current?.title == "CLI")
    }

    @Test func urlAlertsSettingPersists() {
        let service = makeService()
        service.urlAlertsEnabled = false
        #expect(!makeService().urlAlertsEnabled)
    }

    @Test func urlAlertsAreLimitedPerMinute() {
        let service = makeService()
        let results = sendURLAlerts(ExternalAlertService.urlRateLimitCapacity + 2, to: service)

        #expect(results.filter { $0 }.count == ExternalAlertService.urlRateLimitCapacity)
        #expect(service.droppedCount == 2)
        #expect(service.handle(jsonLine: #"{"title":"CLI"}"#).contains(#""ok":true"#))
    }

    @Test func urlLimitRecoversAfterAMinute() {
        let service = makeService()
        _ = sendURLAlerts(ExternalAlertService.urlRateLimitCapacity + 1, to: service)

        clock.advance(by: ExternalAlertService.urlRateLimitWindow)
        #expect(service.handle(url: integrationsURL("notchhub://alert?title=later")))
    }
}
