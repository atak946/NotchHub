import Foundation
import Network
import OSLog

enum IntegrationsSocketState: Equatable, Sendable {
    case stopped
    case starting
    case listening
    case failed(String)
}

/// Local socket transport. `onLine` runs on the main actor and returns the reply line (without newline).
protocol IntegrationsSocketServing: AnyObject, Sendable {
    func start(
        path: String,
        onState: @escaping @Sendable (IntegrationsSocketState) -> Void,
        onLine: @escaping @MainActor @Sendable (String) -> String
    )
    func stop()
}

/// Unix domain socket server (Network.framework) accepting newline-delimited JSON requests.
/// The socket file is restricted to the current user (0600). All state is confined to `queue`.
final class IntegrationsSocketServer: IntegrationsSocketServing, @unchecked Sendable {
    static let maxLineBytes = 8192
    static let maxConnections = 8
    static let idleTimeout: DispatchTimeInterval = .seconds(2)
    /// `sockaddr_un.sun_path` holds 104 bytes including the terminating NUL.
    static let maxPathBytes = 103
    static let socketPermissions: mode_t = 0o600
    static let directoryPermissions = 0o700

    private let queue = DispatchQueue(label: "\(AppIdentity.bundleID).Integrations.socket")
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Integrations")
    private var listener: NWListener?
    private var path: String?
    private var connections: [ObjectIdentifier: IntegrationsSocketConnection] = [:]

    init() {}

    func start(
        path: String,
        onState: @escaping @Sendable (IntegrationsSocketState) -> Void,
        onLine: @escaping @MainActor @Sendable (String) -> String
    ) {
        queue.async { [self] in
            guard listener == nil else { return }
            onState(.starting)
            do {
                try prepareSocketPath(path)
                try startListener(path: path, onState: onState, onLine: onLine)
            } catch {
                logger.error("Socket server failed to start: \(error.localizedDescription, privacy: .public)")
                onState(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.stateUpdateHandler = nil
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.cancel() }
            connections = [:]
            if let path { Self.removeSocketFile(at: path) }
            path = nil
        }
    }

    // MARK: - Listener

    private func startListener(
        path: String,
        onState: @escaping @Sendable (IntegrationsSocketState) -> Void,
        onLine: @escaping @MainActor @Sendable (String) -> String
    ) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        self.path = path

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, onLine: onLine)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.handle(state, path: path, onState: onState)
        }
        listener.start(queue: queue)
    }

    private func handle(
        _ state: NWListener.State,
        path: String,
        onState: @escaping @Sendable (IntegrationsSocketState) -> Void
    ) {
        switch state {
        case .ready:
            if chmod(path, Self.socketPermissions) != 0 {
                logger.error("chmod 0600 failed for socket, stopping")
                onState(.failed("Soket izinleri kısıtlanamadı"))
                stop()
                return
            }
            logger.info("Socket listening at \(path, privacy: .public)")
            onState(.listening)
        case .failed(let error):
            logger.error("Socket listener failed: \(error.localizedDescription, privacy: .public)")
            onState(.failed(error.localizedDescription))
            stop()
        case .cancelled:
            onState(.stopped)
        case .setup, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func accept(_ nwConnection: NWConnection, onLine: @escaping @MainActor @Sendable (String) -> String) {
        guard connections.count < Self.maxConnections else {
            logger.notice("Too many socket connections, rejecting")
            nwConnection.cancel()
            return
        }
        let connection = IntegrationsSocketConnection(
            connection: nwConnection,
            queue: queue,
            maxLineBytes: Self.maxLineBytes,
            idleTimeout: Self.idleTimeout,
            onLine: onLine
        ) { [weak self] id in
            self?.connections[id] = nil
        }
        connections[connection.id] = connection
        connection.start()
    }

    // MARK: - File system

    private func prepareSocketPath(_ path: String) throws {
        guard path.utf8.count <= Self.maxPathBytes else {
            throw IntegrationsSocketError.pathTooLong
        }
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        // Only ever delete a stale socket, never a regular file someone put there.
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw IntegrationsSocketError.pathOccupied }
        Self.removeSocketFile(at: path)
    }

    private static func removeSocketFile(at path: String) {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK else { return }
        unlink(path)
    }
}

enum IntegrationsSocketError: LocalizedError {
    case pathTooLong
    case pathOccupied

    var errorDescription: String? {
        switch self {
        case .pathTooLong: "Soket yolu çok uzun"
        case .pathOccupied: "Soket yolunda soket olmayan bir dosya var"
        }
    }
}

/// One client connection: frames lines, forwards them to the main actor in order and writes replies.
private final class IntegrationsSocketConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let idleTimeout: DispatchTimeInterval
    private let onLine: @MainActor @Sendable (String) -> String
    private let onClose: (ObjectIdentifier) -> Void
    private var buffer: IntegrationsLineBuffer
    private var pendingReplies = 0
    private var peerClosed = false
    private var isClosed = false
    private var idleWork: DispatchWorkItem?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        maxLineBytes: Int,
        idleTimeout: DispatchTimeInterval,
        onLine: @escaping @MainActor @Sendable (String) -> String,
        onClose: @escaping (ObjectIdentifier) -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.idleTimeout = idleTimeout
        self.onLine = onLine
        self.onClose = onClose
        buffer = IntegrationsLineBuffer(maxLineBytes: maxLineBytes)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        resetIdleTimer()
        receive()
    }

    func cancel() {
        close()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                self.consume(data)
            }
            if isComplete || error != nil {
                self.peerClosed = true
                if let rest = self.buffer.flush() { self.dispatch(rest) }
                self.closeIfDone()
            } else if !self.isClosed {
                self.resetIdleTimer()
                self.receive()
            }
        }
    }

    private func consume(_ data: Data) {
        switch buffer.append(data) {
        case .success(let lines):
            lines.forEach(dispatch)
        case .failure:
            send(#"{"ok":false,"error":"line too long"}"#) { [weak self] in self?.close() }
        }
    }

    private func dispatch(_ line: String) {
        pendingReplies += 1
        let onLine = onLine
        let queue = queue
        // The main queue is serial, so replies keep request order.
        DispatchQueue.main.async { [weak self] in
            let reply = MainActor.assumeIsolated { onLine(line) }
            queue.async { [weak self] in
                self?.finishReply(reply)
            }
        }
    }

    private func finishReply(_ reply: String) {
        pendingReplies -= 1
        send(reply) { [weak self] in self?.closeIfDone() }
    }

    private func send(_ reply: String, completion: @escaping @Sendable () -> Void) {
        guard !isClosed else { return }
        connection.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in completion() })
    }

    private func closeIfDone() {
        queue.async { [weak self] in
            guard let self, self.peerClosed, self.pendingReplies == 0 else { return }
            self.close()
        }
    }

    private func resetIdleTimer() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        idleWork = work
        queue.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        idleWork?.cancel()
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose(id)
    }
}
