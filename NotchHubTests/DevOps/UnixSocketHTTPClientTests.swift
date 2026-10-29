import Darwin
import Foundation
import Testing
@testable import NotchHub

/// One-shot Unix domain socket server: accepts one client, reads the request head, writes `response` in pieces, closes.
final class DevOpsUnixSocketServer: @unchecked Sendable {
    let path: String
    private let descriptor: Int32

    init(response: [String]) throws {
        path = "/tmp/nh-\(UUID().uuidString.prefix(8)).sock"
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                _ = path.withCString { strncpy(buffer, $0, capacity - 1) }
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            close(descriptor)
            throw POSIXError(.EADDRINUSE)
        }

        let listener = descriptor
        Thread.detachNewThread {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            _ = read(client, &buffer, buffer.count)
            for piece in response {
                let bytes = Array(piece.utf8)
                _ = bytes.withUnsafeBytes { write(client, $0.baseAddress, bytes.count) }
                usleep(20_000)
            }
            close(client)
        }
    }

    deinit {
        close(descriptor)
        unlink(path)
    }
}

struct UnixSocketHTTPClientTests {
    @Test func getsContentLengthBodyOverUnixSocket() async throws {
        let server = try DevOpsUnixSocketServer(response: [
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 47\r\n\r\n",
            "[{\"Id\":\"a\",\"Names\":[\"/web\"],\"State\":\"running\"}]",
        ])
        let body = try await UnixSocketHTTPClient.get(socketPath: server.path, path: "/containers/json?all=1")
        let containers = try DockerContainerSummary.decodeList(body)
        #expect(containers.map(\.name) == ["web"])
    }

    @Test func streamsChunkedDockerEvents() async throws {
        let first = "{\"Type\":\"container\",\"Action\":\"die\",\"Actor\":{\"ID\":\"c1\",\"Attributes\":{\"name\":\"api\",\"exitCode\":\"3\"}},\"time\":1}\n"
        let second = "{\"Type\":\"container\",\"Action\":\"oom\",\"Actor\":{\"ID\":\"c2\",\"Attributes\":{\"name\":\"db\"}},\"time\":2}\n"
        let splitAt = first.index(first.startIndex, offsetBy: 30)
        let server = try DevOpsUnixSocketServer(response: [
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n",
            String(format: "%x\r\n", first.utf8.count) + String(first[..<splitAt]),
            String(first[splitAt...]) + "\r\n",
            String(format: "%x\r\n", second.utf8.count) + second + "\r\n",
            "0\r\n\r\n",
        ])

        var received: [DockerEvent] = []
        for try await event in SocketDockerEngineClient().events(socketPath: server.path) {
            received.append(event)
        }
        #expect(received.map(\.kind) == [.die, .oom])
        #expect(received.first?.exitCode == 3)
        #expect(received.last?.containerName == "db")
    }

    @Test func missingSocketFails() async {
        await #expect(throws: (any Error).self) {
            try await UnixSocketHTTPClient.get(socketPath: "/tmp/nh-missing-\(UUID().uuidString.prefix(6)).sock", path: "/")
        }
    }

    @Test func nonSuccessStatusThrows() async throws {
        let server = try DevOpsUnixSocketServer(response: ["HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n"])
        await #expect(throws: UnixSocketHTTPError.unexpectedStatus(500)) {
            try await UnixSocketHTTPClient.get(socketPath: server.path, path: "/containers/json")
        }
    }
}
