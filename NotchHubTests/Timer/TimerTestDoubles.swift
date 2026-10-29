import Foundation
@testable import NotchHub

/// Manually advanced clock. `sleep` never returns before cancellation, so tests drive `refresh()` explicitly.
final class FakeTimerClock: TimerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSinceReferenceDate: 1_000_000)) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

@MainActor
final class FakeTimerNotifier: TimerNotifier {
    private(set) var prepareCount = 0
    private(set) var completions: [TimerCompletion] = []

    func prepare() {
        prepareCount += 1
    }

    func timerDidFinish(_ completion: TimerCompletion) {
        completions.append(completion)
    }
}

func makeTimerTestDefaults() -> UserDefaults {
    let (suiteName, defaults) = TestDefaults.makeSuite("Timer.\(UUID().uuidString)")
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
