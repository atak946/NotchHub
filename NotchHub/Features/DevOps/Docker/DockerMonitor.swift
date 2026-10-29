import AppKit
import Foundation
import Observation
import OSLog

/// Writes plain text to the clipboard, injectable for tests.
@MainActor
protocol DevOpsPasteboard: AnyObject {
    func copy(_ text: String)
}

@MainActor
final class SystemDevOpsPasteboard: DevOpsPasteboard {
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Watches the local Docker daemon (OrbStack, Docker Desktop, colima) and alerts on container failures.
@MainActor
@Observable
final class DockerMonitor {
    /// Periodic recount; events keep counts fresh in between (and trigger a recount each).
    static let refreshInterval: Duration = .seconds(15)
    /// The recount backs off to this while the counts stay the same.
    static let maxRefreshInterval: Duration = .seconds(60)
    /// How long a died/OOM container keeps the compact badge red.
    static let recentFailureWindow: TimeInterval = 10 * 60
    static let logTailLines = 100

    private enum Keys {
        static let isEnabled = "Docker.isEnabled"
        static let alertsEnabled = "Docker.alertsEnabled"
        static let ignoreStopExits = "Docker.ignoreStopExits"
    }

    @ObservationIgnored private let alerts: NotchAlertCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: any DockerEngineClient
    @ObservationIgnored private let fileSystem: any DevOpsFileSystem
    @ObservationIgnored private let clock: any DevOpsClock
    @ObservationIgnored private let pasteboard: any DevOpsPasteboard
    @ObservationIgnored private var policy: DockerAlertPolicy
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let refreshLoop: PowerAwareLoop
    /// Recounts in a row that found the same counts; drives the back-off.
    @ObservationIgnored private var unchangedRecounts = 0
    @ObservationIgnored private let logger = Logger(subsystem: DevOpsConstants.logSubsystem, category: "Docker")

    private(set) var daemonState: DockerDaemonState = .stopped
    private(set) var counts: DockerContainerCounts = .zero
    private(set) var socketPath: String?
    private(set) var lastFailure: DockerAlertDecision?
    private(set) var lastFailureAt: Date?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            isEnabled ? start() : stop()
        }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    /// Ignore 143/137 exits that follow a `kill` event (i.e. `docker stop` / `compose down`).
    var ignoreStopExits: Bool {
        didSet {
            defaults.set(ignoreStopExits, forKey: Keys.ignoreStopExits)
            policy.ignoreStopExits = ignoreStopExits
        }
    }

    init(
        alerts: NotchAlertCenter,
        defaults: UserDefaults = .standard,
        client: any DockerEngineClient = SocketDockerEngineClient(),
        fileSystem: any DevOpsFileSystem = LocalDevOpsFileSystem(),
        clock: any DevOpsClock = SystemDevOpsClock(),
        pasteboard: (any DevOpsPasteboard)? = nil
    ) {
        self.alerts = alerts
        self.defaults = defaults
        self.client = client
        self.fileSystem = fileSystem
        self.clock = clock
        refreshLoop = PowerAwareLoop(sleep: { try await clock.sleep(for: $0) })
        self.pasteboard = pasteboard ?? SystemDevOpsPasteboard()
        let ignoreStops = defaults.object(forKey: Keys.ignoreStopExits) as? Bool ?? true
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        ignoreStopExits = ignoreStops
        policy = DockerAlertPolicy(ignoreStopExits: ignoreStops)
    }

    // MARK: - Derived state

    var isRunning: Bool { daemonState == .running }

    var hasRecentFailure: Bool {
        guard let lastFailureAt else { return false }
        return clock.now.timeIntervalSince(lastFailureAt) <= Self.recentFailureWindow
    }

    /// Red badge beside the closed notch while a container is unhealthy or died recently.
    var hasCompactIndicator: Bool {
        isEnabled && (counts.unhealthy > 0 || hasRecentFailure)
    }

    // MARK: - Lifecycle

    func start() {
        guard isEnabled, runTask == nil else { return }
        logger.info("Docker monitor started")
        runTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        stopRefreshing()
        daemonState = .stopped
        socketPath = nil
    }

    // MARK: - Event handling (internal for tests)

    func apply(containers: [DockerContainerSummary]) {
        counts = DockerContainerCounts(containers)
        policy.seed(with: containers)
    }

    func handle(_ event: DockerEvent) {
        guard let decision = policy.evaluate(event) else { return }
        logger.info("Docker alert: \(String(describing: decision), privacy: .public)")
        if decision.isFailure {
            lastFailure = decision
            lastFailureAt = clock.now
        }
        guard alertsEnabled else { return }
        alerts.post(makeAlert(for: decision))
    }

    static func logsCommand(for name: String) -> String {
        "docker logs --tail \(logTailLines) \(name)"
    }

    // MARK: - Connection loop

    private func runLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            if let path = DockerSocketLocator.resolve(fileSystem: fileSystem) {
                socketPath = path
                daemonState = attempt == 0 ? .connecting : .reconnecting(attempt: attempt)
                if await session(socketPath: path) {
                    attempt = 0
                }
            } else {
                socketPath = nil
                daemonState = .socketNotFound
                counts = .zero
            }
            guard !Task.isCancelled else { return }
            attempt += 1
            if daemonState == .running {
                daemonState = .reconnecting(attempt: attempt)
            }
            do {
                try await clock.sleep(for: DockerReconnectBackoff.delay(forAttempt: attempt))
            } catch {
                return
            }
        }
    }

    /// One connected session: list containers, then follow the event stream. Returns whether it connected.
    private func session(socketPath: String) async -> Bool {
        do {
            apply(containers: try await client.containers(socketPath: socketPath))
        } catch {
            logger.debug("Docker daemon unreachable: \(String(describing: error), privacy: .public)")
            return false
        }
        daemonState = .running
        startRefreshing(socketPath: socketPath)
        defer { stopRefreshing() }
        do {
            for try await event in client.events(socketPath: socketPath) {
                handle(event)
                await refreshCounts(socketPath: socketPath)
            }
            logger.info("Docker event stream closed")
        } catch {
            logger.info("Docker event stream failed: \(String(describing: error), privacy: .public)")
        }
        return true
    }

    private func startRefreshing(socketPath: String) {
        stopRefreshing()
        // The session just listed the containers, so the first loop run only schedules the next recount.
        var isFirstRun = true
        refreshLoop.start { [weak self] in
            guard let self else { return nil }
            if isFirstRun {
                isFirstRun = false
            } else {
                await self.refreshCounts(socketPath: socketPath)
            }
            return PowerAwareScheduler.backoff(
                base: Self.refreshInterval, maximum: Self.maxRefreshInterval, unchangedCount: self.unchangedRecounts
            )
        }
    }

    private func stopRefreshing() {
        refreshLoop.stop()
        unchangedRecounts = 0
    }

    private func refreshCounts(socketPath: String) async {
        do {
            let fresh = DockerContainerCounts(try await client.containers(socketPath: socketPath))
            unchangedRecounts = fresh == counts ? unchangedRecounts + 1 : 0
            counts = fresh
        } catch {
            logger.debug("Docker recount failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Alerts

    private func makeAlert(for decision: DockerAlertDecision) -> NotchAlert {
        let name = decision.containerName
        let key = "docker.container.\(name)"
        switch decision {
        case .died(_, let exitCode):
            let command = Self.logsCommand(for: name)
            let pasteboard = pasteboard
            return NotchAlert(
                module: .status,
                systemImage: "shippingbox.fill",
                title: String(localized: "\(name) sonlandı"),
                subtitle: String(localized: "Çıkış kodu \(exitCode)"),
                style: .urgent,
                coalescingKey: key,
                autoDismissAfter: NotchAlert.importantDuration,
                actionTitle: String(localized: "Günlük komutunu kopyala"),
                action: { pasteboard.copy(command) }
            )
        case .outOfMemory:
            return NotchAlert(
                module: .status,
                systemImage: "memorychip.fill",
                title: String(localized: "\(name) belleği doldurdu"),
                subtitle: String(localized: "Container OOM nedeniyle sonlandırıldı"),
                style: .urgent,
                coalescingKey: key,
                autoDismissAfter: NotchAlert.importantDuration
            )
        case .unhealthy:
            return NotchAlert(
                module: .status,
                systemImage: "heart.slash.fill",
                title: String(localized: "\(name) sağlıksız"),
                subtitle: String(localized: "Sağlık kontrolü başarısız"),
                style: .reminder,
                coalescingKey: key
            )
        case .recovered:
            return NotchAlert(
                module: .status,
                systemImage: "heart.fill",
                title: String(localized: "\(name) düzeldi"),
                subtitle: String(localized: "Sağlık kontrolü başarılı"),
                style: .success,
                coalescingKey: key
            )
        }
    }
}
