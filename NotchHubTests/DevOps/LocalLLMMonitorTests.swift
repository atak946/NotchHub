import Foundation
import Testing
@testable import NotchHub

struct LocalLLMResponseParserTests {
    @Test func parsesLMStudioModels() throws {
        let json = """
        {"data":[{"id":"qwen2.5-coder-7b-instruct","object":"model","owned_by":"organization_owner"},
                 {"id":"text-embedding-nomic-embed-text-v1.5","object":"model"}],"object":"list"}
        """
        #expect(try LocalLLMResponseParser.lmStudioModels(devOpsData(json)) == [
            "qwen2.5-coder-7b-instruct", "text-embedding-nomic-embed-text-v1.5",
        ])
    }

    @Test func parsesOllamaTagsAndPs() throws {
        let tags = """
        {"models":[{"name":"llama3.2:latest","model":"llama3.2:latest","size":2019393189,"details":{"family":"llama"}}]}
        """
        let ps = """
        {"models":[{"model":"qwen2.5:7b","size_vram":5000000000}]}
        """
        #expect(try LocalLLMResponseParser.ollamaModels(devOpsData(tags)) == ["llama3.2:latest"])
        #expect(try LocalLLMResponseParser.ollamaModels(devOpsData(ps)) == ["qwen2.5:7b"])
        #expect(try LocalLLMResponseParser.ollamaModels(devOpsData("{\"models\":[]}")).isEmpty)
    }

    @Test func rejectsUnexpectedShapes() {
        #expect(throws: LocalLLMResponseParser.ParseError.unexpectedShape) {
            try LocalLLMResponseParser.lmStudioModels(devOpsData("{\"error\":\"nope\"}"))
        }
        #expect(throws: LocalLLMResponseParser.ParseError.unexpectedShape) {
            try LocalLLMResponseParser.ollamaModels(devOpsData("<html>"))
        }
    }

    @Test func buildsLocalhostURLs() {
        #expect(LocalLLMMonitor.lmStudioURL(port: 1234)?.absoluteString == "http://localhost:1234/v1/models")
        #expect(LocalLLMMonitor.ollamaURL(port: 11434, path: "/api/tags")?.absoluteString == "http://localhost:11434/api/tags")
    }
}

@MainActor
struct LocalLLMMonitorTests {
    private let defaults = makeDevOpsTestDefaults()
    private let alerts = makeDevOpsAlertCenter()
    private let fetcher = DevOpsFakeFetcher()

    private func makeMonitor() -> LocalLLMMonitor {
        LocalLLMMonitor(alerts: alerts, defaults: defaults, fetcher: fetcher, clock: DevOpsTestClock())
    }

    private func serveLMStudio() {
        fetcher.set("/v1/models", port: 1234, json: "{\"data\":[{\"id\":\"gemma-3-12b\"}]}")
    }

    @Test func defaultsAreEnabledWithAlertsOff() {
        let monitor = makeMonitor()
        #expect(monitor.isEnabled)
        #expect(!monitor.alertsEnabled)
        #expect(monitor.lmStudioPort == 1234)
        #expect(monitor.ollamaPort == 11434)
    }

    @Test func reportsActiveServerAndModels() async {
        let monitor = makeMonitor()
        fetcher.set("/api/tags", port: 11434, json: "{\"models\":[{\"name\":\"a\"},{\"name\":\"b\"}]}")
        fetcher.set("/api/ps", port: 11434, json: "{\"models\":[]}")

        await monitor.refresh()
        #expect(monitor.activeServer == .ollama)
        #expect(monitor.ollama.installedModelCount == 2)
        #expect(monitor.ollama.loadedModels.isEmpty)
        #expect(monitor.lmStudio.reachability == .down)

        serveLMStudio()
        await monitor.refresh()
        #expect(monitor.activeServer == .lmStudio)
        #expect(monitor.primaryModelName == "gemma-3-12b")
    }

    @Test func noAlertsByDefault() async {
        let monitor = makeMonitor()
        await monitor.refresh()
        serveLMStudio()
        await monitor.refresh()
        #expect(alerts.current == nil)
    }

    @Test func alertsOnlyOnTransitionsWhenEnabled() async {
        let monitor = makeMonitor()
        monitor.alertsEnabled = true

        serveLMStudio()
        await monitor.refresh()
        #expect(alerts.current == nil)  // first observation is not a transition

        await monitor.refresh()
        #expect(alerts.current == nil)

        fetcher.clear()
        await monitor.refresh()
        #expect(alerts.current?.title == "LM Studio durdu")

        serveLMStudio()
        await monitor.refresh()
        #expect(alerts.current?.title == "LM Studio başladı")
        #expect(alerts.current?.subtitle == "gemma-3-12b")
    }

    @Test func nonSuccessStatusCountsAsDown() async {
        let monitor = makeMonitor()
        fetcher.set("/v1/models", port: 1234, json: "{}", status: 500)
        await monitor.refresh()
        #expect(monitor.lmStudio.reachability == .down)
    }

    @Test func portIsClampedAndPersisted() async {
        let monitor = makeMonitor()
        monitor.lmStudioPort = 70000
        #expect(monitor.lmStudioPort == 65535)
        monitor.ollamaPort = 8080
        #expect(makeMonitor().ollamaPort == 8080)
    }
}
