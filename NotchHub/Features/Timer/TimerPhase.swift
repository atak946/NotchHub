import Foundation

/// What the timer is currently counting down.
enum TimerPhase: String, CaseIterable, Equatable, Sendable {
    /// A plain one-off countdown (presets or custom duration).
    case countdown
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .countdown: String(localized: "Zamanlayıcı")
        case .work: String(localized: "Odak")
        case .shortBreak: String(localized: "Kısa Mola")
        case .longBreak: String(localized: "Uzun Mola")
        }
    }

    var systemImage: String {
        switch self {
        case .countdown: "timer"
        case .work: "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "figure.walk"
        }
    }

    var isBreak: Bool {
        self == .shortBreak || self == .longBreak
    }
}

/// UI-facing state of `TimerService`.
enum TimerState: Equatable, Sendable {
    case idle
    case running(TimerPhase)
    case paused(TimerPhase)
    case finished(TimerPhase)

    var phase: TimerPhase? {
        switch self {
        case .idle: nil
        case .running(let phase), .paused(let phase), .finished(let phase): phase
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}

/// Emitted by `TimerEngine` when a phase runs out (or is skipped).
struct TimerCompletion: Equatable, Sendable {
    let finishedPhase: TimerPhase
    /// Phase that follows in a Pomodoro cycle; `nil` for a plain countdown.
    let nextPhase: TimerPhase?
    /// `true` when the next phase was started automatically.
    let didAutoStartNext: Bool
}
