import Foundation
import Synchronization

struct ProfilesProcessResult: Equatable, Sendable {
    let exitCode: Int32
    /// Last few KB of combined stdout/stderr.
    let outputTail: String
}

/// Runs an executable with an argument array (never through a shell).
protocol ProfilesProcessRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String],
        timeout: Duration
    ) async throws -> ProfilesProcessResult
}

struct LiveProfilesProcessRunner: ProfilesProcessRunning {
    static let maxCapturedBytes = 8 * 1024

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String],
        timeout: Duration
    ) async throws -> ProfilesProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let box = ProfilesProcessBox(process: process)
        let output = ProfilesOutputBuffer(limit: Self.maxCapturedBytes)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData)
        }
        defer { pipe.fileHandleForReading.readabilityHandler = nil }

        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            box.terminate(timedOut: true)
        }
        defer { timeoutTask.cancel() }

        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                    if Task.isCancelled { box.terminate(timedOut: false) }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: ProfileStepFailure(message: String(localized: "\(executable.lastPathComponent) başlatılamadı: \(error.localizedDescription)")))
                }
            }
        } onCancel: {
            box.terminate(timedOut: false)
        }

        try Task.checkCancellation()
        if box.didTimeOut {
            throw ProfileStepFailure(message: String(localized: "\(executable.lastPathComponent) zaman aşımına uğradı"))
        }
        return ProfilesProcessResult(exitCode: exitCode, outputTail: output.text)
    }
}

/// Thread-safe handle so cancellation and timeout can terminate the child from any thread.
private final class ProfilesProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var timedOut = false

    init(process: Process) {
        self.process = process
    }

    var didTimeOut: Bool { lock.withLock { timedOut } }

    func terminate(timedOut isTimeout: Bool) {
        lock.withLock {
            guard process.isRunning else { return }
            timedOut = timedOut || isTimeout
            process.terminate()
        }
    }
}

private final class ProfilesOutputBuffer: Sendable {
    private let data = Mutex(Data())
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        data.withLock { buffer in
            buffer.append(chunk)
            if buffer.count > limit {
                buffer = Data(buffer.suffix(limit))
            }
        }
    }

    var text: String {
        data.withLock { String(decoding: $0, as: UTF8.self) }
    }
}
