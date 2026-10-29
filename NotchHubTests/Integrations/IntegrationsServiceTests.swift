import Foundation
import Testing
@testable import NotchHub

@MainActor
struct IntegrationsServiceTests {
    private let alerts = NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    private let defaults = makeIntegrationsTestDefaults()
    private let system = IntegrationsFakeSystem()
    private let server = IntegrationsFakeSocketServer()
    private let clock = IntegrationsTestClock()

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

    @Test func initHasNoSideEffects() {
        let service = makeService()
        #expect(service.isEnabled)
        #expect(service.socketState == .stopped)
        #expect(server.startedPaths.isEmpty)
        #expect(service.countToday == 0)
        #expect(service.lastAlert == nil)
    }

    @Test func startAndStopAreIdempotent() {
        let service = makeService()
        service.start()
        service.start()
        #expect(server.startedPaths == ["/tmp/notchhub-test.sock"])
        #expect(service.socketState == .starting)
        service.stop()
        service.stop()
        #expect(server.stopCount == 1)
        #expect(service.socketState == .stopped)
    }

    @Test func togglingEnabledControlsSocketAndPersists() {
        let service = makeService()
        service.start()
        service.isEnabled = false
        #expect(server.stopCount == 1)
        #expect(defaults.bool(forKey: "Integrations.enabled") == false)
        service.isEnabled = true
        #expect(server.startedPaths.count == 2)
        #expect(makeService().isEnabled)
    }

    @Test func handleURLPostsAlert() throws {
        let service = makeService()
        let handled = service.handle(url: integrationsURL(
            "notchhub://alert?title=Deploy&subtitle=prod&style=urgent&icon=hammer.fill&duration=0&key=deploy"
        ))
        #expect(handled)
        let alert = try #require(alerts.current)
        #expect(alert.title == "Deploy")
        #expect(alert.subtitle == "prod")
        #expect(alert.style == .urgent)
        #expect(alert.systemImage == "hammer.fill")
        #expect(alert.autoDismissAfter == nil)
        #expect(alert.coalescingKey == "external.deploy")
        #expect(alert.module == nil)
        #expect(alert.actionTitle == nil)
        #expect(service.countToday == 1)
        #expect(service.lastAlert?.title == "Deploy")
        #expect(service.lastAlert?.source == .url)
    }

    @Test func unknownSymbolFallsBackToBell() {
        let service = makeService()
        service.handle(url: integrationsURL("notchhub://alert?title=x&icon=made.up.symbol"))
        #expect(alerts.current?.systemImage == "bell")
    }

    @Test func rejectsForeignAndInvalidURLs() {
        let service = makeService()
        #expect(!service.handle(url: integrationsURL("https://example.com")))
        #expect(!service.handle(url: integrationsURL("notchhub://alert?style=urgent")))
        #expect(alerts.current == nil)
        #expect(service.countToday == 0)
    }

    @Test func disabledServiceRejectsEverything() {
        let service = makeService()
        service.isEnabled = false
        #expect(!service.handle(url: integrationsURL("notchhub://alert?title=x")))
        #expect(service.handle(jsonLine: #"{"title":"x"}"#).contains(#""ok":false"#))
        #expect(alerts.current == nil)
    }

    @Test func globalGateBlocksPosting() {
        let service = makeService()
        service.shouldPostAlert = { false }
        #expect(!service.handle(url: integrationsURL("notchhub://alert?title=x")))
        #expect(alerts.current == nil)
    }

    @Test func openRequestCallsHandler() {
        let service = makeService()
        var opened: [IntegrationsOpenTarget] = []
        service.onOpenModule = { opened.append($0) }
        #expect(service.handle(url: integrationsURL("notchhub://open?module=status")))
        #expect(opened == [.status])
        #expect(alerts.current == nil)
    }

    @Test func webOpenURLBecomesOpenAction() throws {
        let service = makeService()
        service.handle(url: integrationsURL("notchhub://alert?title=PR&open=https://github.com/x/y/pull/1"))
        #expect(alerts.current?.actionTitle == ExternalAlertService.openActionTitle)
        alerts.performAction()
        #expect(system.openedURLs.map(\.absoluteString) == ["https://github.com/x/y/pull/1"])
        #expect(system.revealedURLs.isEmpty)
    }

    @Test func fileOpenURLIsOnlyRevealed() {
        let service = makeService()
        service.handle(url: integrationsURL("notchhub://alert?title=Report&open=file:///Applications/Evil.app"))
        #expect(alerts.current?.actionTitle == ExternalAlertService.revealActionTitle)
        alerts.performAction()
        #expect(system.openedURLs.isEmpty)
        #expect(system.revealedURLs.map(\.path) == ["/Applications/Evil.app"])
    }

    @Test func rateLimitDropsExtraRequestsAndRecovers() {
        let service = makeService()
        let results = (0..<12).map { index in
            service.handle(url: integrationsURL("notchhub://alert?title=n\(index)"))
        }
        #expect(results.filter { $0 }.count == 10)
        #expect(service.droppedCount == 2)
        #expect(service.handle(jsonLine: #"{"title":"x"}"#).contains("rate limited"))

        // The URL bucket refills more slowly (10/min) than the shared one.
        clock.advance(by: ExternalAlertService.urlRateLimitWindow / Double(ExternalAlertService.urlRateLimitCapacity))
        #expect(service.handle(url: integrationsURL("notchhub://alert?title=later")))
    }

    @Test func invalidRequestsAlsoConsumeTokens() {
        let service = makeService()
        for _ in 0..<10 { _ = service.handle(jsonLine: "garbage") }
        #expect(service.handle(jsonLine: #"{"title":"x"}"#).contains("rate limited"))
    }

    @Test func jsonRepliesAreWellFormed() throws {
        let service = makeService()
        let ok = service.handle(jsonLine: #"{"title":"x","bogus":1}"#)
        let okObject = try #require(try JSONSerialization.jsonObject(with: Data(ok.utf8)) as? [String: Any])
        #expect(okObject["ok"] as? Bool == true)
        #expect((okObject["warnings"] as? [String])?.first == "Ignored unknown parameter 'bogus'")

        let bad = service.handle(jsonLine: #"{"title":"x","style":"\"quoted\""}"#)
        let badObject = try #require(try JSONSerialization.jsonObject(with: Data(bad.utf8)) as? [String: Any])
        #expect(badObject["ok"] as? Bool == false)
        #expect((badObject["error"] as? String)?.contains("invalid style") == true)
        #expect(service.lastAlert?.source == .socket)
    }

    @Test func dailyCountResetsAndPersists() {
        let service = makeService()
        service.handle(url: integrationsURL("notchhub://alert?title=a"))
        service.handle(url: integrationsURL("notchhub://alert?title=b"))
        #expect(service.countToday == 2)
        #expect(makeService().countToday == 2)
        #expect(makeService().lastAlert?.title == "b")

        clock.advance(by: 86_400)
        #expect(service.countToday == 0)
        service.handle(url: integrationsURL("notchhub://alert?title=c"))
        #expect(service.countToday == 1)
    }

    @Test func testAlertBypassesRateLimit() {
        let service = makeService()
        for index in 0..<10 { service.handle(url: integrationsURL("notchhub://alert?title=n\(index)")) }
        service.sendTestAlert()
        #expect(service.lastAlert?.source == .test)
        #expect(service.countToday == 11)
    }

    @Test func zshSetupLineUsesBundledPathWhenAvailable() {
        let service = makeService()
        #expect(service.zshSetupLine == "source '\(ExternalAlertService.zshHookPlaceholderPath)'")
        #expect(!service.isZshHookBundled)
        system.bundledZshHookPath = "/Applications/Notch Hub.app/Contents/Resources/notchhub.zsh"
        #expect(service.zshSetupLine == "source '/Applications/Notch Hub.app/Contents/Resources/notchhub.zsh'")
        service.copyZshSetupLine()
        #expect(system.copiedTexts == [service.zshSetupLine])
    }

    @Test func shellQuotingEscapesSingleQuotes() {
        #expect(ExternalAlertService.shellQuoted("/a/it's") == #"'/a/it'\''s'"#)
    }

    @Test func defaultSocketPathFitsSunPath() {
        let path = ExternalAlertService.defaultSocketPath()
        #expect(path.hasSuffix("/NotchHub/notchhub.sock"))
        #expect(path.utf8.count <= IntegrationsSocketServer.maxPathBytes)
    }
}
