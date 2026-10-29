import Foundation
import Observation
import OSLog

/// Polls LM Studio and Ollama on localhost and reports which one is serving which model.
@MainActor
@Observable
final class LocalLLMMonitor {
    static let pollInterval: Duration = .seconds(15)
    /// The poll backs off to this while neither server changes (e.g. both stay down all day).
    static let maxPollInterval: Duration = .seconds(30)
    static let portRange = 1...65535

    private enum Keys {
        static let isEnabled = "LocalLLM.isEnabled"
        static let alertsEnabled = "LocalLLM.alertsEnabled"
        static let lmStudioPort = "LocalLLM.lmStudioPort"
        static let ollamaPort = "LocalLLM.ollamaPort"
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetcher: any LocalLLMHTTPFetching
    @ObservationIgnored private let clock: any DevOpsClock
    @ObservationIgnored private let loop: PowerAwareLoop
    /// Polls in a row where neither server changed; drives the back-off.
    @ObservationIgnored private var unchangedPolls = 0
    @ObservationIgnored private let logger = Logger(subsystem: DevOpsConstants.logSubsystem, category: "LocalLLM")

    private(set) var lmStudio = LocalLLMServerStatus()
    private(set) var ollama = LocalLLMServerStatus()

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            isEnabled ? start() : stop()
        }
    }

    /// Transition alerts are opt-in.
    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    var lmStudioPort: Int {
        didSet {
            let valid = Self.clampPort(lmStudioPort)
            if valid != lmStudioPort { lmStudioPort = valid }
            defaults.set(valid, forKey: Keys.lmStudioPort)
            lmStudio = LocalLLMServerStatus()
        }
    }

    var ollamaPort: Int {
        didSet {
            let valid = Self.clampPort(ollamaPort)
            if valid != ollamaPort { ollamaPort = valid }
            defaults.set(valid, forKey: Keys.ollamaPort)
            ollama = LocalLLMServerStatus()
        }
    }

    init(
        alerts: NotchAlertCenter,
        defaults: UserDefaults = .standard,
        fetcher: any LocalLLMHTTPFetching = URLSessionLocalLLMFetcher(),
        clock: any DevOpsClock = SystemDevOpsClock()
    ) {
        self.alerts = alerts
        self.defaults = defaults
        self.fetcher = fetcher
        self.clock = clock
        loop = PowerAwareLoop(sleep: { try await clock.sleep(for: $0) })
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? false
        lmStudioPort = Self.clampPort(defaults.object(forKey: Keys.lmStudioPort) as? Int ?? LocalLLMServerKind.defaultLMStudioPort)
        ollamaPort = Self.clampPort(defaults.object(forKey: Keys.ollamaPort) as? Int ?? LocalLLMServerKind.defaultOllamaPort)
    }

    // MARK: - Derived state

    func status(for kind: LocalLLMServerKind) -> LocalLLMServerStatus {
        switch kind {
        case .lmStudio: lmStudio
        case .ollama: ollama
        }
    }

    /// First reachable server, LM Studio preferred.
    var activeServer: LocalLLMServerKind? {
        LocalLLMServerKind.allCases.first { status(for: $0).isUp }
    }

    var primaryModelName: String? {
        activeServer.flatMap { status(for: $0).loadedModels.first }
    }

    // MARK: - Lifecycle

    func start() {
        guard isEnabled, !loop.isActive else { return }
        loop.start { [weak self] in
            guard let self else { return nil }
            await self.refresh()
            return PowerAwareScheduler.backoff(
                base: Self.pollInterval, maximum: Self.maxPollInterval, unchangedCount: self.unchangedPolls
            )
        }
    }

    func stop() {
        loop.stop()
        unchangedPolls = 0
        lmStudio = LocalLLMServerStatus()
        ollama = LocalLLMServerStatus()
    }

    /// Polls both servers once. Internal for tests.
    func refresh() async {
        async let lmStudioResult = fetchLMStudio(port: lmStudioPort)
        async let ollamaResult = fetchOllama(port: ollamaPort)
        let (newLMStudio, newOllama) = await (lmStudioResult, ollamaResult)
        let isUnchanged = newLMStudio == lmStudio && newOllama == ollama
        unchangedPolls = isUnchanged ? unchangedPolls + 1 : 0
        update(.lmStudio, to: newLMStudio)
        update(.ollama, to: newOllama)
    }

    nonisolated static func lmStudioURL(port: Int) -> URL? {
        URL(string: "http://localhost:\(port)/v1/models")
    }

    nonisolated static func ollamaURL(port: Int, path: String) -> URL? {
        URL(string: "http://localhost:\(port)\(path)")
    }

    // MARK: - Private

    private func update(_ kind: LocalLLMServerKind, to newStatus: LocalLLMServerStatus) {
        let old = status(for: kind)
        switch kind {
        case .lmStudio: lmStudio = newStatus
        case .ollama: ollama = newStatus
        }
        guard old.reachability != .unknown, old.reachability != newStatus.reachability else { return }
        logger.info("\(kind.title, privacy: .public) is now \(newStatus.isUp ? "up" : "down", privacy: .public)")
        guard alertsEnabled else { return }
        alerts.post(NotchAlert(
            module: .status,
            systemImage: "cpu",
            title: newStatus.isUp ? String(localized: "\(kind.title) başladı") : String(localized: "\(kind.title) durdu"),
            subtitle: newStatus.isUp ? newStatus.loadedModels.first : nil,
            style: newStatus.isUp ? .success : .info,
            coalescingKey: "localllm.\(kind.rawValue)"
        ))
    }

    private func fetchLMStudio(port: Int) async -> LocalLLMServerStatus {
        guard let url = Self.lmStudioURL(port: port), let data = await fetchOK(url) else {
            return LocalLLMServerStatus(reachability: .down)
        }
        let models = (try? LocalLLMResponseParser.lmStudioModels(data)) ?? []
        return LocalLLMServerStatus(reachability: .up, loadedModels: models)
    }

    private func fetchOllama(port: Int) async -> LocalLLMServerStatus {
        guard let tagsURL = Self.ollamaURL(port: port, path: "/api/tags"), let tags = await fetchOK(tagsURL) else {
            return LocalLLMServerStatus(reachability: .down)
        }
        let installed = (try? LocalLLMResponseParser.ollamaModels(tags)) ?? []
        var loaded: [String] = []
        if let psURL = Self.ollamaURL(port: port, path: "/api/ps"), let running = await fetchOK(psURL) {
            loaded = (try? LocalLLMResponseParser.ollamaModels(running)) ?? []
        }
        return LocalLLMServerStatus(reachability: .up, loadedModels: loaded, installedModelCount: installed.count)
    }

    private func fetchOK(_ url: URL) async -> Data? {
        do {
            let (data, status) = try await fetcher.get(url)
            return (200..<300).contains(status) ? data : nil
        } catch {
            return nil
        }
    }

    private static func clampPort(_ port: Int) -> Int {
        min(max(port, portRange.lowerBound), portRange.upperBound)
    }
}
