import Foundation

/// Wall-clock time and sleeping for the System monitors, injectable for tests.
protocol SystemClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemLiveClock: SystemClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await PowerAwareScheduler.sleep(for: duration)
    }
}

/// One pending delayed action; scheduling again replaces it. Used to settle debouncers.
@MainActor
final class SystemDelayedAction {
    private let clock: any SystemClock
    private var task: Task<Void, Never>?

    init(clock: any SystemClock) {
        self.clock = clock
    }

    var isScheduled: Bool { task != nil }

    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        task?.cancel()
        let clock = clock
        task = Task { [weak self] in
            do {
                try await clock.sleep(for: .seconds(max(interval, 0)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Runs an action repeatedly at a (power-scaled) interval until stopped. The first run happens after one
/// interval; returning from away or Low Power Mode runs it immediately (e.g. to catch listeners missed in sleep).
@MainActor
final class SystemPoller {
    private let loop: PowerAwareLoop

    init(clock: any SystemClock, priority: PollingPriority = .standard, power: (any PowerConditionsProviding)? = nil) {
        loop = PowerAwareLoop(priority: priority, power: power, sleep: { try await clock.sleep(for: $0) })
    }

    var isRunning: Bool { loop.isActive }

    func start(every interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        guard !loop.isActive else { return }
        let period = Duration.seconds(interval)
        var isFirstRun = true
        loop.start {
            if isFirstRun {
                isFirstRun = false
            } else {
                action()
            }
            return period
        }
    }

    func stop() {
        loop.stop()
    }
}
