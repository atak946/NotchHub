import Foundation
@testable import NotchHub

/// Manually advanced clock; `sleep` blocks until cancelled so loops never spin in tests.
final class DevOpsTestClock: DevOpsClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }

    func set(_ date: Date) {
        lock.withLock { current = date }
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

struct DevOpsFakeFileSystem: DevOpsFileSystem {
    var homeDirectoryPath: String
    var sockets: Set<String>

    func isSocket(atPath path: String) -> Bool {
        sockets.contains(path)
    }
}

final class DevOpsFakeProber: EndpointProber, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [EndpointProbeResult] = []
    private var fallback = EndpointProbeResult(statusCode: 200, latency: 0.1)
    private(set) var probeCount = 0

    func enqueue(_ results: EndpointProbeResult...) {
        lock.withLock { queued.append(contentsOf: results) }
    }

    func probe(_ endpoint: MonitoredEndpoint) async -> EndpointProbeResult {
        lock.withLock {
            probeCount += 1
            return queued.isEmpty ? fallback : queued.removeFirst()
        }
    }
}

final class DevOpsFakeVPN: VPNDetector, @unchecked Sendable {
    private let lock = NSLock()
    private var active: Bool

    init(active: Bool) {
        self.active = active
    }

    func setActive(_ value: Bool) {
        lock.withLock { active = value }
    }

    func isVPNActive() -> Bool {
        lock.withLock { active }
    }
}

final class DevOpsFakeFetcher: LocalLLMHTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: (Data, Int)] = [:]

    func set(_ path: String, port: Int, json: String, status: Int = 200) {
        lock.withLock { responses["\(port)\(path)"] = (Data(json.utf8), status) }
    }

    func clear() {
        lock.withLock { responses = [:] }
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        let key = "\(url.port ?? 0)\(url.path())"
        guard let response = lock.withLock({ responses[key] }) else {
            throw URLError(.cannotConnectToHost)
        }
        return response
    }
}

@MainActor
final class DevOpsFakePasteboard: DevOpsPasteboard {
    private(set) var copied: [String] = []

    func copy(_ text: String) {
        copied.append(text)
    }
}

struct DevOpsFakeDockerClient: DockerEngineClient {
    func containers(socketPath: String) async throws -> [DockerContainerSummary] {
        throw UnixSocketHTTPError.closedBeforeResponse
    }

    func events(socketPath: String) -> AsyncThrowingStream<DockerEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
func makeDevOpsAlertCenter() -> NotchAlertCenter {
    NotchAlertCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
}

@MainActor
func devOpsAllAlerts(_ center: NotchAlertCenter) -> [NotchAlert] {
    (center.current.map { [$0] } ?? []) + center.queue
}

func makeDevOpsTestDefaults() -> UserDefaults {
    let suiteName = "NotchHubTests.DevOps.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Could not create test defaults")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func devOpsData(_ text: String) -> Data {
    Data(text.utf8)
}
