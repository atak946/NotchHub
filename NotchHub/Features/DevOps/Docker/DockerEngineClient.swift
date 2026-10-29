import Foundation
import OSLog

/// Docker Engine API calls used by `DockerMonitor`, injectable for tests.
protocol DockerEngineClient: Sendable {
    func containers(socketPath: String) async throws -> [DockerContainerSummary]
    /// Long-lived event stream; finishes when the daemon closes the connection.
    func events(socketPath: String) -> AsyncThrowingStream<DockerEvent, Error>
}

/// Talks to the daemon over its Unix socket using `UnixSocketHTTPClient`.
struct SocketDockerEngineClient: DockerEngineClient {
    static let containersPath = "/containers/json?all=1"
    static let subscribedEvents = ["die", "oom", "kill", "start", "destroy", "health_status"]

    private static let logger = Logger(subsystem: DevOpsConstants.logSubsystem, category: "Docker")

    /// `/events?filters=…` with the JSON filter percent-encoded.
    static var eventsPath: String {
        let quoted = subscribedEvents.map { "\"\($0)\"" }.joined(separator: ",")
        let filters = "{\"type\":[\"container\"],\"event\":[\(quoted)]}"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = filters.addingPercentEncoding(withAllowedCharacters: allowed) ?? filters
        return "/events?filters=\(encoded)"
    }

    func containers(socketPath: String) async throws -> [DockerContainerSummary] {
        let body = try await UnixSocketHTTPClient.get(socketPath: socketPath, path: Self.containersPath)
        return try DockerContainerSummary.decodeList(body)
    }

    func events(socketPath: String) -> AsyncThrowingStream<DockerEvent, Error> {
        let source = UnixSocketHTTPClient.stream(socketPath: socketPath, path: Self.eventsPath)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var splitter = NewlineDelimitedSplitter()
                    for try await event in source {
                        switch event {
                        case .head(let head):
                            guard (200..<300).contains(head.statusCode) else {
                                throw UnixSocketHTTPError.unexpectedStatus(head.statusCode)
                            }
                        case .body(let data):
                            for record in try splitter.append(data) {
                                Self.yield(record, to: continuation)
                            }
                        case .end:
                            if let record = splitter.flush() {
                                Self.yield(record, to: continuation)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func yield(_ record: Data, to continuation: AsyncThrowingStream<DockerEvent, Error>.Continuation) {
        do {
            continuation.yield(try DockerEvent.decode(record))
        } catch {
            logger.debug("Skipping undecodable Docker event: \(String(describing: error), privacy: .public)")
        }
    }
}
