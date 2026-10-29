import Foundation

/// What a Docker event should tell the user, if anything.
enum DockerAlertDecision: Equatable, Sendable {
    case died(name: String, exitCode: Int)
    case outOfMemory(name: String)
    case unhealthy(name: String)
    case recovered(name: String)

    var containerName: String {
        switch self {
        case .died(let name, _), .outOfMemory(let name), .unhealthy(let name), .recovered(let name):
            name
        }
    }

    /// `true` for failures that should light the compact badge.
    var isFailure: Bool {
        switch self {
        case .died, .outOfMemory: true
        case .unhealthy, .recovered: false
        }
    }
}

/// Pure decision logic turning the raw event stream into alerts.
///
/// - Exit code 0 never alerts.
/// - With `ignoreStopExits`, a `die` with 143 (SIGTERM) or 137 (SIGKILL after the stop timeout)
///   that follows a `kill` event for the same container within `stopWindow` is treated as `docker stop`.
/// - A `die` right after an `oom` is swallowed because the OOM alert already fired.
/// - Health alerts only fire on transitions (unhealthy once, recovered only after unhealthy).
struct DockerAlertPolicy: Sendable {
    /// `docker stop` escalates to SIGKILL after 10 s by default; leave margin for slow daemons.
    static let stopWindow: TimeInterval = 20
    static let oomWindow: TimeInterval = 20
    static let stopExitCodes: Set<Int> = [143, 137]

    var ignoreStopExits: Bool

    private var lastKill: [String: Date] = [:]
    private var lastOOM: [String: Date] = [:]
    private var unhealthyIDs: Set<String> = []

    init(ignoreStopExits: Bool = true) {
        self.ignoreStopExits = ignoreStopExits
    }

    /// Seeds health knowledge from a container listing so a later "healthy" counts as recovery.
    mutating func seed(with containers: [DockerContainerSummary]) {
        unhealthyIDs = Set(containers.filter(\.isUnhealthy).map(\.id))
    }

    mutating func evaluate(_ event: DockerEvent) -> DockerAlertDecision? {
        prune(now: event.time)
        let id = event.containerID
        switch event.kind {
        case .kill:
            lastKill[id] = event.time
            return nil
        case .oom:
            lastOOM[id] = event.time
            return .outOfMemory(name: event.containerName)
        case .die:
            return evaluateDie(event)
        case .destroy:
            forget(id)
            return nil
        case .health(.unhealthy):
            guard unhealthyIDs.insert(id).inserted else { return nil }
            return .unhealthy(name: event.containerName)
        case .health(.healthy):
            guard unhealthyIDs.remove(id) != nil else { return nil }
            return .recovered(name: event.containerName)
        case .health(.starting), .start, .other:
            return nil
        }
    }

    private mutating func evaluateDie(_ event: DockerEvent) -> DockerAlertDecision? {
        let id = event.containerID
        let killedAt = lastKill.removeValue(forKey: id)
        let oomAt = lastOOM.removeValue(forKey: id)
        unhealthyIDs.remove(id)

        guard let code = event.exitCode, code != 0 else { return nil }
        if let oomAt, event.time.timeIntervalSince(oomAt) <= Self.oomWindow {
            return nil
        }
        if ignoreStopExits,
           Self.stopExitCodes.contains(code),
           let killedAt,
           event.time.timeIntervalSince(killedAt) <= Self.stopWindow {
            return nil
        }
        return .died(name: event.containerName, exitCode: code)
    }

    private mutating func forget(_ id: String) {
        lastKill[id] = nil
        lastOOM[id] = nil
        unhealthyIDs.remove(id)
    }

    private mutating func prune(now: Date) {
        let horizon = max(Self.stopWindow, Self.oomWindow)
        lastKill = lastKill.filter { now.timeIntervalSince($0.value) <= horizon }
        lastOOM = lastOOM.filter { now.timeIntervalSince($0.value) <= horizon }
    }
}

/// Exponential reconnect delay: 1, 2, 4 … capped at 60 seconds.
enum DockerReconnectBackoff {
    static let initialSeconds = 1
    static let maxSeconds = 60

    static func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .seconds(initialSeconds) }
        let exponent = min(attempt - 1, 6)
        return .seconds(min(initialSeconds << exponent, maxSeconds))
    }
}
