import Foundation
import Network
import OSLog

enum UnixSocketHTTPError: Error, Equatable, Sendable {
    case connectionFailed(String)
    case closedBeforeResponse
    case unexpectedStatus(Int)
    case responseTooLarge
}

/// Sends one HTTP/1.1 GET over a Unix domain socket (Network.framework) and streams the decoded response.
enum UnixSocketHTTPClient {
    static let maxBufferedBodyBytes = 16 * 1024 * 1024

    /// Raw request bytes. `Host` is required by HTTP/1.1; Docker ignores its value.
    static func requestData(path: String) -> Data {
        Data("GET \(path) HTTP/1.1\r\nHost: docker\r\nUser-Agent: NotchHub\r\nAccept: application/json\r\nConnection: close\r\n\r\n".utf8)
    }

    /// Streams parser events; cancelling the consuming task closes the connection.
    static func stream(socketPath: String, path: String) -> AsyncThrowingStream<HTTPResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let session = UnixSocketHTTPSession(socketPath: socketPath, continuation: continuation)
            continuation.onTermination = { _ in session.cancel() }
            session.start(request: requestData(path: path))
        }
    }

    /// Performs a complete request and returns the body when the status is 2xx.
    static func get(socketPath: String, path: String) async throws -> Data {
        var body = Data()
        var status: Int?
        for try await event in stream(socketPath: socketPath, path: path) {
            switch event {
            case .head(let head):
                status = head.statusCode
            case .body(let chunk):
                body.append(chunk)
                guard body.count <= maxBufferedBodyBytes else { throw UnixSocketHTTPError.responseTooLarge }
            case .end:
                break
            }
        }
        guard let status else { throw UnixSocketHTTPError.closedBeforeResponse }
        guard (200..<300).contains(status) else { throw UnixSocketHTTPError.unexpectedStatus(status) }
        return body
    }
}

/// Owns one `NWConnection`. All mutable state is confined to `queue`.
private final class UnixSocketHTTPSession: @unchecked Sendable {
    private static let receiveChunkBytes = 64 * 1024
    private static let logger = Logger(subsystem: DevOpsConstants.logSubsystem, category: "DockerSocket")

    private let connection: NWConnection
    private let continuation: AsyncThrowingStream<HTTPResponseEvent, Error>.Continuation
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleID).DevOps.unix-http")
    private var parser = HTTPResponseParser()
    private var isFinished = false

    init(socketPath: String, continuation: AsyncThrowingStream<HTTPResponseEvent, Error>.Continuation) {
        connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        self.continuation = continuation
    }

    func start(request: Data) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state: state, request: request)
        }
        connection.start(queue: queue)
    }

    func cancel() {
        queue.async { [self] in
            isFinished = true
            connection.cancel()
        }
    }

    private func handle(state: NWConnection.State, request: Data) {
        switch state {
        case .ready:
            connection.send(content: request, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    self.fail(UnixSocketHTTPError.connectionFailed(error.localizedDescription))
                } else {
                    self.receive()
                }
            })
        case .failed(let error), .waiting(let error):
            fail(UnixSocketHTTPError.connectionFailed(error.localizedDescription))
        case .cancelled:
            finish(nil)
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunkBytes) {
            [weak self] content, _, isComplete, error in
            guard let self, !self.isFinished else { return }
            do {
                if let content, !content.isEmpty {
                    try self.deliver(self.parser.feed(content))
                }
                if self.parser.isComplete {
                    self.finish(nil)
                    return
                }
                if let error {
                    throw UnixSocketHTTPError.connectionFailed(error.localizedDescription)
                }
                if isComplete {
                    try self.deliver(self.parser.finish())
                    self.finish(nil)
                    return
                }
                self.receive()
            } catch {
                self.fail(error)
            }
        }
    }

    private func deliver(_ events: [HTTPResponseEvent]) throws {
        for event in events {
            continuation.yield(event)
        }
    }

    private func fail(_ error: Error) {
        guard !isFinished else { return }
        Self.logger.debug("Unix socket request failed: \(String(describing: error), privacy: .public)")
        finish(error)
    }

    private func finish(_ error: Error?) {
        guard !isFinished else { return }
        isFinished = true
        if let error {
            continuation.finish(throwing: error)
        } else if parser.isComplete {
            continuation.finish()
        } else {
            continuation.finish(throwing: UnixSocketHTTPError.closedBeforeResponse)
        }
        connection.cancel()
    }
}
