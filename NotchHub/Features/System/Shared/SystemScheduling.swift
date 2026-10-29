import Foundation

/// Wall-clock time and sleeping for the System monitors, injectable for tests.
protocol SystemClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemLiveClock: SystemClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
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

/// Runs an action repeatedly at a fixed interval until stopped.
@MainActor
final class SystemPoller {
    private let clock: any SystemClock
    private var task: Task<Void, Never>?

    init(clock: any SystemClock) {
        self.clock = clock
    }

    var isRunning: Bool { task != nil }

    func start(every interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        guard task == nil else { return }
        let clock = clock
        task = Task {
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
