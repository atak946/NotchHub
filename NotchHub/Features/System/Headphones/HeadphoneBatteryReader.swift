import Foundation
import OSLog

/// Reads battery levels for one device; called at most once per connect event.
protocol HeadphoneBatteryReading: Sendable {
    func readLevels(deviceName: String, timeout: Duration) async -> HeadphoneBatteryLevels?
}

/// Runs `system_profiler SPBluetoothDataType -json` once (no permission needed) and parses it.
struct SystemProfilerBatteryReader: HeadphoneBatteryReading {
    private static let executable = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    private static let arguments = ["SPBluetoothDataType", "-json"]

    func readLevels(deviceName: String, timeout: Duration) async -> HeadphoneBatteryLevels? {
        let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Headphones")
        do {
            let data = try await HeadphoneProcess.output(of: Self.executable, arguments: Self.arguments, timeout: timeout)
            let levels = HeadphoneBatteryParser.parseSystemProfiler(data, deviceName: deviceName)
            if levels == nil { logger.info("No battery levels reported for the connected headset") }
            return levels
        } catch {
            logger.error("Reading headset battery failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

enum HeadphoneProcessError: LocalizedError {
    case timedOut
    case failed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .timedOut: "system_profiler timed out"
        case .failed(let status): "system_profiler exited with status \(status)"
        }
    }
}

/// One-shot subprocess on a background queue with a hard timeout (never through a shell).
enum HeadphoneProcess {
    static func output(of executable: URL, arguments: [String], timeout: Duration) async throws -> Data {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try runBlocking(executable: executable, arguments: arguments, timeoutSeconds: seconds)
                })
            }
        }
    }

    private static func runBlocking(executable: URL, arguments: [String], timeoutSeconds: Double) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()

        let box = HeadphoneProcessBox(process: process)
        let watchdog = DispatchWorkItem { box.terminateForTimeout() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        if box.didTimeOut { throw HeadphoneProcessError.timedOut }
        guard process.terminationStatus == 0 else {
            throw HeadphoneProcessError.failed(status: process.terminationStatus)
        }
        return data
    }
}

/// Lets the watchdog terminate the child from another queue.
private final class HeadphoneProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var timedOut = false

    init(process: Process) {
        self.process = process
    }

    var didTimeOut: Bool { lock.withLock { timedOut } }

    func terminateForTimeout() {
        lock.withLock {
            guard process.isRunning else { return }
            timedOut = true
            process.terminate()
        }
    }
}
