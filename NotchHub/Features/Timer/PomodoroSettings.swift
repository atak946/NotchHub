import Foundation

/// User-configurable Pomodoro cycle. Durations are whole minutes.
struct PomodoroSettings: Equatable, Sendable {
    static let workMinutesRange = 1...120
    static let shortBreakMinutesRange = 1...60
    static let longBreakMinutesRange = 1...120
    static let sessionsRange = 1...12

    static let `default` = PomodoroSettings(
        workMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        sessionsBeforeLongBreak: 4,
        autoStartNextPhase: false
    )

    private static let secondsPerMinute: TimeInterval = 60

    var workMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var sessionsBeforeLongBreak: Int
    var autoStartNextPhase: Bool

    /// Copy with every value forced into its valid range.
    func clamped() -> PomodoroSettings {
        PomodoroSettings(
            workMinutes: workMinutes.clamped(to: Self.workMinutesRange),
            shortBreakMinutes: shortBreakMinutes.clamped(to: Self.shortBreakMinutesRange),
            longBreakMinutes: longBreakMinutes.clamped(to: Self.longBreakMinutesRange),
            sessionsBeforeLongBreak: sessionsBeforeLongBreak.clamped(to: Self.sessionsRange),
            autoStartNextPhase: autoStartNextPhase
        )
    }

    /// Length of a Pomodoro phase in seconds. A plain countdown has no configured length.
    func duration(of phase: TimerPhase) -> TimeInterval {
        let minutes: Int = switch phase {
        case .work: workMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        case .countdown: 0
        }
        return TimeInterval(minutes) * Self.secondsPerMinute
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
