import Foundation

/// Wall-clock time and loop pacing for Insights services, injectable for tests.
protocol InsightsClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemInsightsClock: InsightsClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await PowerAwareScheduler.sleep(for: duration)
    }
}
