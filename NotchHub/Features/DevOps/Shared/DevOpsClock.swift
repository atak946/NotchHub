import Foundation

/// Wall-clock time and sleeping for the DevOps monitors, injectable for tests.
protocol DevOpsClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemDevOpsClock: DevOpsClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Shared constants of the DevOps feature folder.
enum DevOpsConstants {
    static let logSubsystem = AppIdentity.logSubsystem
}
