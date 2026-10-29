import Foundation

/// Container health as reported by Docker health checks.
enum DockerHealthStatus: String, Equatable, Sendable {
    case starting
    case healthy
    case unhealthy
}

/// The subset of Docker container events NotchHub reacts to.
enum DockerEventKind: Equatable, Sendable {
    case die
    case oom
    case kill
    case start
    case destroy
    case health(DockerHealthStatus)
    case other(String)

    init(action: String) {
        let trimmed = action.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(Self.healthPrefix) {
            let value = trimmed.dropFirst(Self.healthPrefix.count).trimmingCharacters(in: .whitespaces)
            if let status = DockerHealthStatus(rawValue: value) {
                self = .health(status)
                return
            }
            self = .other(trimmed)
            return
        }
        switch trimmed {
        case "die": self = .die
        case "oom": self = .oom
        case "kill": self = .kill
        case "start": self = .start
        case "destroy": self = .destroy
        default: self = .other(trimmed)
        }
    }

    private static let healthPrefix = "health_status:"
}

/// A decoded entry of Docker's `/events` stream.
struct DockerEvent: Equatable, Sendable {
    let kind: DockerEventKind
    let containerID: String
    let containerName: String
    let exitCode: Int?
    let signal: Int?
    let time: Date

    init(kind: DockerEventKind, containerID: String, containerName: String, exitCode: Int? = nil, signal: Int? = nil, time: Date) {
        self.kind = kind
        self.containerID = containerID
        self.containerName = containerName
        self.exitCode = exitCode
        self.signal = signal
        self.time = time
    }

    enum DecodingFailure: Error, Equatable {
        case notAContainerEvent
        case missingContainerID
    }

    private static let nanosecondsPerSecond: Double = 1_000_000_000
    private static let shortIDLength = 12

    /// Decodes one JSON line. Supports both modern (`Type`/`Action`/`Actor`) and legacy (`status`/`id`) fields.
    static func decode(_ data: Data) throws -> DockerEvent {
        let raw = try JSONDecoder().decode(RawEvent.self, from: data)
        let type = raw.type ?? raw.legacyType ?? "container"
        guard type == "container" else { throw DecodingFailure.notAContainerEvent }
        guard let id = raw.actor?.id ?? raw.id, !id.isEmpty else { throw DecodingFailure.missingContainerID }

        let attributes = raw.actor?.attributes ?? [:]
        let action = raw.action ?? raw.status ?? ""
        let name = attributes["name"].flatMap { $0.isEmpty ? nil : $0 } ?? String(id.prefix(shortIDLength))
        let time: Date
        if let nanos = raw.timeNano {
            time = Date(timeIntervalSince1970: Double(nanos) / nanosecondsPerSecond)
        } else {
            time = Date(timeIntervalSince1970: Double(raw.time ?? 0))
        }
        return DockerEvent(
            kind: DockerEventKind(action: action),
            containerID: id,
            containerName: name,
            exitCode: attributes["exitCode"].flatMap { Int($0) },
            signal: attributes["signal"].flatMap { Int($0) },
            time: time
        )
    }

    private struct RawEvent: Decodable {
        let type: String?
        let legacyType: String?
        let action: String?
        let status: String?
        let id: String?
        let actor: RawActor?
        let time: Int64?
        let timeNano: Int64?

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case legacyType = "type"
            case action = "Action"
            case status
            case id
            case actor = "Actor"
            case time
            case timeNano
        }
    }

    private struct RawActor: Decodable {
        let id: String?
        let attributes: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case attributes = "Attributes"
        }
    }
}

/// One entry of `GET /containers/json?all=1`.
struct DockerContainerSummary: Equatable, Sendable {
    let id: String
    let name: String
    let state: String
    let health: DockerHealthStatus?

    var isRunning: Bool { state == "running" }
    var isUnhealthy: Bool { health == .unhealthy }

    static func decodeList(_ data: Data) throws -> [DockerContainerSummary] {
        try JSONDecoder().decode([RawSummary].self, from: data).map(\.summary)
    }

    private struct RawSummary: Decodable {
        let id: String
        let names: [String]?
        let state: String?
        let status: String?
        let health: RawHealth?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case names = "Names"
            case state = "State"
            case status = "Status"
            case health = "Health"
        }

        var summary: DockerContainerSummary {
            let name = names?.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(id.prefix(12))
            return DockerContainerSummary(id: id, name: name, state: state ?? "unknown", health: resolvedHealth)
        }

        /// Newer daemons report `Health.Status`; older ones only embed it in the human `Status` text.
        private var resolvedHealth: DockerHealthStatus? {
            if let value = health?.status, let parsed = DockerHealthStatus(rawValue: value) {
                return parsed
            }
            guard let status else { return nil }
            if status.contains("(unhealthy)") { return .unhealthy }
            if status.contains("(healthy)") { return .healthy }
            if status.contains("(health: starting)") { return .starting }
            return nil
        }
    }

    private struct RawHealth: Decodable {
        let status: String?

        enum CodingKeys: String, CodingKey {
            case status = "Status"
        }
    }
}

/// Aggregated counts shown on the tile.
struct DockerContainerCounts: Equatable, Sendable {
    var running: Int
    var total: Int
    var unhealthy: Int

    static let zero = DockerContainerCounts(running: 0, total: 0, unhealthy: 0)

    init(running: Int, total: Int, unhealthy: Int) {
        self.running = running
        self.total = total
        self.unhealthy = unhealthy
    }

    init(_ containers: [DockerContainerSummary]) {
        running = containers.filter(\.isRunning).count
        total = containers.count
        unhealthy = containers.filter(\.isUnhealthy).count
    }
}

/// Reachability of the Docker daemon.
enum DockerDaemonState: Equatable, Sendable {
    case stopped
    case socketNotFound
    case connecting
    case running
    case reconnecting(attempt: Int)

    var title: String {
        switch self {
        case .stopped: String(localized: "Kapalı")
        case .socketNotFound: String(localized: "Çalışmıyor")
        case .connecting: String(localized: "Bağlanıyor…")
        case .running: String(localized: "Çalışıyor")
        case .reconnecting: String(localized: "Yeniden bağlanıyor…")
        }
    }
}
