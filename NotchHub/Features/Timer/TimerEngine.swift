import Foundation

/// Pure value-type state machine for a plain countdown and a Pomodoro cycle.
///
/// Running phases store an absolute end date instead of accumulating ticks, so the
/// remaining time stays correct across sleep/wake and late or missed ticks.
struct TimerEngine: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case countdown
        case pomodoro
    }

    enum Status: Equatable, Sendable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    /// Shortest countdown accepted by `start(duration:now:)`.
    static let minimumDuration: TimeInterval = 1

    private(set) var mode: Mode = .countdown
    private(set) var status: Status = .idle
    private(set) var phase: TimerPhase = .countdown
    /// Full length of the current phase, used for progress.
    private(set) var phaseDuration: TimeInterval = 0
    /// Work sessions completed since the Pomodoro cycle started.
    private(set) var completedWorkSessions = 0
    /// Pomodoro configuration; changes take effect from the next phase.
    var settings: PomodoroSettings {
        didSet { settings = settings.clamped() }
    }

    init(settings: PomodoroSettings = .default) {
        self.settings = settings.clamped()
    }

    // MARK: - Commands

    mutating func start(duration: TimeInterval, now: Date) {
        mode = .countdown
        completedWorkSessions = 0
        begin(phase: .countdown, duration: max(duration, Self.minimumDuration), now: now)
    }

    mutating func startPomodoro(now: Date) {
        mode = .pomodoro
        completedWorkSessions = 0
        begin(phase: .work, duration: settings.duration(of: .work), now: now)
    }

    mutating func pause(now: Date) {
        guard case .running = status else { return }
        status = .paused(remaining: remaining(at: now))
    }

    mutating func resume(now: Date) {
        guard case .paused(let remaining) = status else { return }
        status = .running(endDate: now.addingTimeInterval(remaining))
    }

    mutating func cancel() {
        self = TimerEngine(settings: settings)
    }

    /// Advances time. Returns a completion when the running phase reached its end date.
    @discardableResult
    mutating func tick(now: Date) -> TimerCompletion? {
        guard case .running(let endDate) = status, now >= endDate else { return nil }
        return completeCurrentPhase(now: now, autoStart: settings.autoStartNextPhase)
    }

    /// Pomodoro only: ends the current phase early and starts the next one right away.
    /// From `.finished` it simply starts the upcoming phase.
    @discardableResult
    mutating func skipPhase(now: Date) -> TimerCompletion? {
        guard mode == .pomodoro else { return nil }
        switch status {
        case .idle:
            return nil
        case .finished:
            startNextPhase(now: now)
            return nil
        case .running, .paused:
            return completeCurrentPhase(now: now, autoStart: true)
        }
    }

    /// Pomodoro only: starts the upcoming phase after a finished one.
    mutating func startNextPhase(now: Date) {
        guard mode == .pomodoro, status == .finished, let next = upcomingPhase else { return }
        begin(phase: next, duration: settings.duration(of: next), now: now)
    }

    // MARK: - Queries

    func remaining(at now: Date) -> TimeInterval {
        switch status {
        case .idle, .finished: 0
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    /// Elapsed fraction of the current phase, 0…1.
    func progress(at now: Date) -> Double {
        switch status {
        case .idle: return 0
        case .finished: return 1
        case .running, .paused:
            guard phaseDuration > 0 else { return 0 }
            return min(max(1 - remaining(at: now) / phaseDuration, 0), 1)
        }
    }

    /// Phase that follows the current one in a Pomodoro cycle; `nil` for a countdown or when idle.
    var upcomingPhase: TimerPhase? {
        guard mode == .pomodoro, status != .idle else { return nil }
        let isCurrentCounted = status == .finished
        let completed = phase == .work && !isCurrentCounted ? completedWorkSessions + 1 : completedWorkSessions
        return Self.phase(after: phase, completedWorkSessions: completed, sessionsBeforeLongBreak: settings.sessionsBeforeLongBreak)
    }

    /// Filled session dots for the current cycle (0…`sessionsBeforeLongBreak`).
    var completedSessionsInCycle: Int {
        let perCycle = settings.sessionsBeforeLongBreak
        guard mode == .pomodoro, completedWorkSessions > 0 else { return 0 }
        let inCycle = completedWorkSessions % perCycle
        let isCycleComplete = inCycle == 0 && (phase == .longBreak || (phase == .work && status == .finished))
        return isCycleComplete ? perCycle : inCycle
    }

    // MARK: - Private

    private mutating func begin(phase: TimerPhase, duration: TimeInterval, now: Date) {
        self.phase = phase
        phaseDuration = duration
        status = .running(endDate: now.addingTimeInterval(duration))
    }

    private mutating func completeCurrentPhase(now: Date, autoStart: Bool) -> TimerCompletion {
        let finished = phase
        if finished == .work {
            completedWorkSessions += 1
        }
        guard mode == .pomodoro else {
            status = .finished
            return TimerCompletion(finishedPhase: finished, nextPhase: nil, didAutoStartNext: false)
        }
        let next = Self.phase(
            after: finished,
            completedWorkSessions: completedWorkSessions,
            sessionsBeforeLongBreak: settings.sessionsBeforeLongBreak
        )
        if autoStart {
            begin(phase: next, duration: settings.duration(of: next), now: now)
        } else {
            status = .finished
        }
        return TimerCompletion(finishedPhase: finished, nextPhase: next, didAutoStartNext: autoStart)
    }

    private static func phase(
        after phase: TimerPhase,
        completedWorkSessions: Int,
        sessionsBeforeLongBreak: Int
    ) -> TimerPhase {
        switch phase {
        case .work:
            completedWorkSessions % sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak, .countdown:
            .work
        }
    }
}
