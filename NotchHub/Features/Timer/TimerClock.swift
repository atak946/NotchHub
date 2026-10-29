import Foundation

/// Source of wall-clock time and tick pacing, injectable for tests.
protocol TimerClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemTimerClock: TimerClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
