import Foundation
import Network
import Testing
@testable import NotchHub

/// Real Unix-socket round trips against `IntegrationsSocketServer`.
@MainActor
@Suite(.serialized)
struct IntegrationsSocketServerTests {
    private static let timeout: Duration = .seconds(5)

    private static func makeSocketPath() -> String {
        // Short path: sun_path is limited to 104 bytes.
        "/tmp/nh-\(UUID().uuidString.prefix(8)).sock"
    }

    private static func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw IntegrationsSocketTestError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func listensWithOwnerOnlyPermissionsAndAnswersLines() async throws {
        let path = Self.makeSocketPath()
        let server = IntegrationsSocketServer()
        let states = IntegrationsSocketStateBox()
        var received: [String] = []
        server.start(path: path, onState: { states.append($0) }, onLine: { line in
            received.append(line)
            return #"{"ok":true}"#
        })
        defer { server.stop() }

        try await Self.waitFor { states.contains(.listening) }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect((attributes[.type] as? FileAttributeType) == .typeSocket)

        let reply = try await IntegrationsSocketClient.send("{\"title\":\"one\"}\n{\"title\":\"two\"}\n", to: path)
        #expect(reply == "{\"ok\":true}\n{\"ok\":true}\n")
        #expect(received == [#"{"title":"one"}"#, #"{"title":"two"}"#])
    }

    @Test func overlongLineIsRejected() async throws {
        let path = Self.makeSocketPath()
        let server = IntegrationsSocketServer()
        let states = IntegrationsSocketStateBox()
        server.start(path: path, onState: { states.append($0) }, onLine: { _ in "unexpected" })
        defer { server.stop() }
        try await Self.waitFor { states.contains(.listening) }

        let payload = String(repeating: "a", count: IntegrationsSocketServer.maxLineBytes + 10)
        let reply = try await IntegrationsSocketClient.send(payload, to: path)
        #expect(reply.contains("line too long"))
    }

    @Test func refusesToReplaceRegularFile() async throws {
        let path = Self.makeSocketPath()
        #expect(FileManager.default.createFile(atPath: path, contents: Data("keep".utf8)))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let server = IntegrationsSocketServer()
        let states = IntegrationsSocketStateBox()
        server.start(path: path, onState: { states.append($0) }, onLine: { _ in "" })
        defer { server.stop() }

        try await Self.waitFor { states.values.contains { if case .failed = $0 { true } else { false } } }
        #expect(FileManager.default.contents(atPath: path) == Data("keep".utf8))
    }

    @Test func stopRemovesSocketFile() async throws {
        let path = Self.makeSocketPath()
        let server = IntegrationsSocketServer()
        let states = IntegrationsSocketStateBox()
        server.start(path: path, onState: { states.append($0) }, onLine: { _ in "" })
        try await Self.waitFor { states.contains(.listening) }
        server.stop()
        try await Self.waitFor { !FileManager.default.fileExists(atPath: path) }
    }
}

enum IntegrationsSocketTestError: Error {
    case timeout
    case connectionFailed
}

final class IntegrationsSocketStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [IntegrationsSocketState] = []

    var values: [IntegrationsSocketState] { lock.withLock { _values } }

    func append(_ state: IntegrationsSocketState) {
        lock.withLock { _values.append(state) }
    }

    func contains(_ state: IntegrationsSocketState) -> Bool {
        values.contains(state)
    }
}

/// Minimal client: sends `payload`, half-closes, collects the reply until the server closes.
enum IntegrationsSocketClient {
    static func send(_ payload: String, to path: String) async throws -> String {
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        let queue = DispatchQueue(label: "IntegrationsSocketClient")
        let collector = IntegrationsReplyCollector()
        return try await withCheckedThrowingContinuation { continuation in
            collector.onFinish = { result in
                connection.cancel()
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(payload.utf8), isComplete: true, completion: .contentProcessed { _ in })
                    receive(on: connection, collector: collector)
                case .failed, .waiting:
                    collector.finish(.failure(IntegrationsSocketTestError.connectionFailed))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) {
                collector.finish(.failure(IntegrationsSocketTestError.timeout))
            }
        }
    }

    private static func receive(on connection: NWConnection, collector: IntegrationsReplyCollector) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            if let data { collector.append(data) }
            if isComplete || error != nil {
                collector.finish(.success(collector.text))
            } else {
                receive(on: connection, collector: collector)
            }
        }
    }
}

final class IntegrationsReplyCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var finished = false
    var onFinish: ((Result<String, Error>) -> Void)?

    var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    func finish(_ result: Result<String, Error>) {
        let callback: ((Result<String, Error>) -> Void)? = lock.withLock {
            guard !finished else { return nil }
            finished = true
            return onFinish
        }
        callback?(result)
    }
}
