import Foundation
import Observation
import OSLog

/// Observable facade over `TimerEngine`: owns persistence, ticking and finish side effects.
@MainActor
@Observable
final class TimerService {
    static let presets: [TimeInterval] = [5, 15, 25, 45].map { $0 * secondsPerMinute }
    static let customMinutesRange = 1...180
    static let defaultCustomMinutes = 10
    /// Pace of the UI refresh while running; correctness comes from absolute end dates.
    static let tickInterval: Duration = .milliseconds(250)

    private static let secondsPerMinute: TimeInterval = 60

    private enum Keys {
        static let workMinutes = "Timer.workMinutes"
        static let shortBreakMinutes = "Timer.shortBreakMinutes"
        static let longBreakMinutes = "Timer.longBreakMinutes"
        static let sessionsBeforeLongBreak = "Timer.sessionsBeforeLongBreak"
        static let autoStartNextPhase = "Timer.autoStartNextPhase"
        static let customMinutes = "Timer.customMinutes"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: any TimerClock
    @ObservationIgnored private let notifier: any TimerNotifier
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Timer")

    private(set) var engine: TimerEngine
    private(set) var state: TimerState = .idle
    private(set) var remaining: TimeInterval = 0
    /// Incremented on every natural finish; drive shake animations with it.
    private(set) var finishCount = 0

    /// Called on the main actor whenever a phase finishes on its own (not on skip/cancel).
    @ObservationIgnored var onFinish: (@MainActor () -> Void)?

    /// Persisted Pomodoro configuration; values are clamped on assignment.
    var pomodoroSettings: PomodoroSettings {
        didSet {
            let valid = pomodoroSettings.clamped()
            if valid != pomodoroSettings {
                pomodoroSettings = valid
            }
            engine.settings = valid
            savePomodoroSettings()
        }
    }

    /// Last custom duration in minutes, persisted and clamped to `customMinutesRange`.
    var customMinutes: Int {
        didSet {
            let valid = Self.clampCustomMinutes(customMinutes)
            if valid != customMinutes {
                customMinutes = valid
            }
            defaults.set(valid, forKey: Keys.customMinutes)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        clock: any TimerClock = SystemTimerClock(),
        notifier: any TimerNotifier = UserNotificationTimerNotifier()
    ) {
        self.defaults = defaults
        self.clock = clock
        self.notifier = notifier
        let settings = Self.loadPomodoroSettings(from: defaults)
        pomodoroSettings = settings
        engine = TimerEngine(settings: settings)
        customMinutes = Self.clampCustomMinutes(
            defaults.object(forKey: Keys.customMinutes) as? Int ?? Self.defaultCustomMinutes
        )
    }

    // MARK: - Derived state

    /// Elapsed fraction of the current phase, 0…1.
    var progress: Double {
        switch state {
        case .idle: return 0
        case .finished: return 1
        case .running, .paused:
            guard engine.phaseDuration > 0 else { return 0 }
            return min(max(1 - remaining / engine.phaseDuration, 0), 1)
        }
    }

    /// `true` while there is something to show beside the closed notch.
    var hasCompactContent: Bool {
        state.isRunning || state.isPaused
    }

    var isPomodoro: Bool { engine.mode == .pomodoro }
    var upcomingPhase: TimerPhase? { engine.upcomingPhase }
    var completedSessionsInCycle: Int { engine.completedSessionsInCycle }
    var sessionsBeforeLongBreak: Int { engine.settings.sessionsBeforeLongBreak }
    var phaseDuration: TimeInterval { engine.phaseDuration }

    // MARK: - Commands

    func start(duration: TimeInterval) {
        notifier.prepare()
        engine.start(duration: duration, now: clock.now)
        logger.info("Countdown started: \(Int(duration))s")
        sync()
    }

    func startCustom() {
        start(duration: TimeInterval(customMinutes) * Self.secondsPerMinute)
    }

    func startPomodoro() {
        notifier.prepare()
        engine.startPomodoro(now: clock.now)
        logger.info("Pomodoro started")
        sync()
    }

    func pause() {
        engine.pause(now: clock.now)
        sync()
    }

    func resume() {
        engine.resume(now: clock.now)
        sync()
    }

    func cancel() {
        engine.cancel()
        sync()
    }

    /// Pomodoro: ends the current phase (or a finished one) and starts the next.
    func skipPhase() {
        engine.skipPhase(now: clock.now)
        sync()
    }

    /// Pomodoro: starts the upcoming phase after a finished one (when auto-start is off).
    func startNextPhase() {
        engine.startNextPhase(now: clock.now)
        sync()
    }

    /// Re-reads the clock and fires finish side effects. Called by the ticker; exposed for tests.
    func refresh() {
        if let completion = engine.tick(now: clock.now) {
            handle(completion)
        }
        sync()
    }

    // MARK: - Private

    private func handle(_ completion: TimerCompletion) {
        logger.info("Phase finished: \(completion.finishedPhase.rawValue)")
        finishCount += 1
        notifier.timerDidFinish(completion)
        onFinish?()
    }

    private func sync() {
        let now = clock.now
        remaining = engine.remaining(at: now)
        state = Self.state(for: engine)
        updateTicker()
    }

    private func updateTicker() {
        guard state.isRunning else {
            tickTask?.cancel()
            tickTask = nil
            return
        }
        guard tickTask == nil else { return }
        let clock = clock
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.tickInterval)
                } catch {
                    return
                }
                guard let self else { return }
                self.refresh()
            }
        }
    }

    private static func state(for engine: TimerEngine) -> TimerState {
        switch engine.status {
        case .idle: .idle
        case .running: .running(engine.phase)
        case .paused: .paused(engine.phase)
        case .finished: .finished(engine.phase)
        }
    }

    private static func clampCustomMinutes(_ minutes: Int) -> Int {
        min(max(minutes, customMinutesRange.lowerBound), customMinutesRange.upperBound)
    }

    private static func loadPomodoroSettings(from defaults: UserDefaults) -> PomodoroSettings {
        let fallback = PomodoroSettings.default
        return PomodoroSettings(
            workMinutes: defaults.object(forKey: Keys.workMinutes) as? Int ?? fallback.workMinutes,
            shortBreakMinutes: defaults.object(forKey: Keys.shortBreakMinutes) as? Int ?? fallback.shortBreakMinutes,
            longBreakMinutes: defaults.object(forKey: Keys.longBreakMinutes) as? Int ?? fallback.longBreakMinutes,
            sessionsBeforeLongBreak: defaults.object(forKey: Keys.sessionsBeforeLongBreak) as? Int
                ?? fallback.sessionsBeforeLongBreak,
            autoStartNextPhase: defaults.object(forKey: Keys.autoStartNextPhase) as? Bool ?? fallback.autoStartNextPhase
        ).clamped()
    }

    private func savePomodoroSettings() {
        let settings = pomodoroSettings
        defaults.set(settings.workMinutes, forKey: Keys.workMinutes)
        defaults.set(settings.shortBreakMinutes, forKey: Keys.shortBreakMinutes)
        defaults.set(settings.longBreakMinutes, forKey: Keys.longBreakMinutes)
        defaults.set(settings.sessionsBeforeLongBreak, forKey: Keys.sessionsBeforeLongBreak)
        defaults.set(settings.autoStartNextPhase, forKey: Keys.autoStartNextPhase)
    }
}
