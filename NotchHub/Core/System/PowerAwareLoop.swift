import Foundation

/// A poll loop whose interval follows `PowerAwareScheduler`. The body returns the base delay until the next run,
/// or `nil` to idle until `kick()`. Resuming from away or Low Power Mode runs the body immediately.
@MainActor
final class PowerAwareLoop: PowerResumeTarget {
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias Body = @MainActor () async -> Duration?

    private let priority: PollingPriority
    private let power: any PowerConditionsProviding
    private let sleep: Sleeper
    private var body: Body?
    private var task: Task<Void, Never>?
    /// Distinguishes the current task from a cancelled one that is still finishing its body.
    private var generation = 0
    private var isInBody = false
    private var isKickPending = false

    init(
        priority: PollingPriority = .standard,
        power: (any PowerConditionsProviding)? = nil,
        sleep: @escaping Sleeper = { try await PowerAwareScheduler.sleep(for: $0) }
    ) {
        self.priority = priority
        self.power = power ?? PowerConditionsMonitor.shared
        self.sleep = sleep
    }

    /// True between `start` and `stop`, also while idling.
    var isActive: Bool { body != nil }

    /// Runs `body` right away and then on its own schedule. No-op while already active.
    func start(_ body: @escaping Body) {
        guard self.body == nil else { return }
        self.body = body
        power.addResumeTarget(self)
        launch()
    }

    func stop() {
        body = nil
        task?.cancel()
        task = nil
        generation += 1
        isInBody = false
        isKickPending = false
    }

    /// Runs the body now instead of waiting for the current delay (or the idle state) to end.
    func kick() {
        guard body != nil else { return }
        if isInBody {
            isKickPending = true
            return
        }
        launch()
    }

    func powerConditionsDidResume() {
        kick()
    }

    /// The delay the loop would sleep for `base` under the current conditions.
    func scaledDelay(for base: Duration) -> Duration {
        PowerAwareScheduler.interval(base, conditions: power.conditions, priority: priority)
    }

    // MARK: - Private

    private func launch() {
        task?.cancel()
        generation += 1
        let current = generation
        let sleep = sleep
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.runBody(generation: current) else { return }
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
            }
        }
    }

    /// One body run; returns the scaled delay, or `nil` when the loop should end (stopped, stale or idle).
    private func runBody(generation current: Int) async -> Duration? {
        guard current == generation, let body else { return nil }
        while true {
            isInBody = true
            let base = await body()
            guard current == generation else { return nil }
            isInBody = false
            guard isKickPending else {
                guard let base else {
                    task = nil
                    return nil
                }
                return scaledDelay(for: base)
            }
            isKickPending = false
        }
    }
}
