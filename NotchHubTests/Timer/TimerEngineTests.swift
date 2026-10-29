import Foundation
import Testing
@testable import NotchHub

struct TimerEngineTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func pomodoro(
        work: Int = 25,
        short: Int = 5,
        long: Int = 15,
        sessions: Int = 4,
        autoStart: Bool = false
    ) -> TimerEngine {
        TimerEngine(settings: PomodoroSettings(
            workMinutes: work,
            shortBreakMinutes: short,
            longBreakMinutes: long,
            sessionsBeforeLongBreak: sessions,
            autoStartNextPhase: autoStart
        ))
    }

    // MARK: Countdown

    @Test func startsIdle() {
        let engine = TimerEngine()
        #expect(engine.status == .idle)
        #expect(engine.remaining(at: t0) == 0)
        #expect(engine.progress(at: t0) == 0)
        #expect(engine.upcomingPhase == nil)
    }

    @Test func countdownRunsAgainstAbsoluteEndDate() {
        var engine = TimerEngine()
        engine.start(duration: 300, now: t0)

        #expect(engine.status == .running(endDate: t0.addingTimeInterval(300)))
        #expect(engine.phase == .countdown)
        #expect(engine.remaining(at: t0.addingTimeInterval(120)) == 180)
        #expect(engine.progress(at: t0.addingTimeInterval(150)) == 0.5)
        #expect(engine.upcomingPhase == nil)
    }

    @Test func clampsTooShortDuration() {
        var engine = TimerEngine()
        engine.start(duration: -5, now: t0)
        #expect(engine.phaseDuration == TimerEngine.minimumDuration)
    }

    @Test func tickBeforeEndDoesNothing() {
        var engine = TimerEngine()
        engine.start(duration: 60, now: t0)
        #expect(engine.tick(now: t0.addingTimeInterval(59.9)) == nil)
        #expect(engine.status == .running(endDate: t0.addingTimeInterval(60)))
    }

    @Test func detectsFinishEvenWhenTickIsLate() {
        var engine = TimerEngine()
        engine.start(duration: 60, now: t0)

        let completion = engine.tick(now: t0.addingTimeInterval(3600))

        #expect(completion == TimerCompletion(finishedPhase: .countdown, nextPhase: nil, didAutoStartNext: false))
        #expect(engine.status == .finished)
        #expect(engine.remaining(at: t0.addingTimeInterval(3600)) == 0)
        #expect(engine.progress(at: t0) == 1)
        #expect(engine.tick(now: t0.addingTimeInterval(3601)) == nil)
    }

    @Test func pauseFreezesRemainingAndResumeShiftsEndDate() {
        var engine = TimerEngine()
        engine.start(duration: 300, now: t0)
        engine.pause(now: t0.addingTimeInterval(100))

        #expect(engine.status == .paused(remaining: 200))
        #expect(engine.remaining(at: t0.addingTimeInterval(10_000)) == 200)
        #expect(engine.tick(now: t0.addingTimeInterval(10_000)) == nil)

        let resumeAt = t0.addingTimeInterval(10_000)
        engine.resume(now: resumeAt)
        #expect(engine.status == .running(endDate: resumeAt.addingTimeInterval(200)))
    }

    @Test func pauseAndResumeAreIgnoredInWrongStates() {
        var engine = TimerEngine()
        engine.pause(now: t0)
        engine.resume(now: t0)
        #expect(engine.status == .idle)

        engine.start(duration: 60, now: t0)
        engine.resume(now: t0.addingTimeInterval(10))
        #expect(engine.status == .running(endDate: t0.addingTimeInterval(60)))
    }

    @Test func cancelResetsButKeepsSettings() {
        var engine = pomodoro(work: 50)
        engine.startPomodoro(now: t0)
        engine.cancel()

        #expect(engine.status == .idle)
        #expect(engine.mode == .countdown)
        #expect(engine.completedWorkSessions == 0)
        #expect(engine.settings.workMinutes == 50)
    }

    @Test func skipIsIgnoredForCountdown() {
        var engine = TimerEngine()
        engine.start(duration: 60, now: t0)
        #expect(engine.skipPhase(now: t0) == nil)
        #expect(engine.status == .running(endDate: t0.addingTimeInterval(60)))
    }

    // MARK: Pomodoro

    @Test func pomodoroStartsWithWork() {
        var engine = pomodoro()
        engine.startPomodoro(now: t0)

        #expect(engine.mode == .pomodoro)
        #expect(engine.phase == .work)
        #expect(engine.phaseDuration == 25 * 60)
        #expect(engine.upcomingPhase == .shortBreak)
    }

    @Test func workFinishWaitsForUserWithoutAutoStart() {
        var engine = pomodoro()
        engine.startPomodoro(now: t0)

        let completion = engine.tick(now: t0.addingTimeInterval(25 * 60))

        #expect(completion == TimerCompletion(finishedPhase: .work, nextPhase: .shortBreak, didAutoStartNext: false))
        #expect(engine.status == .finished)
        #expect(engine.completedWorkSessions == 1)
        #expect(engine.upcomingPhase == .shortBreak)
        #expect(engine.completedSessionsInCycle == 1)

        let next = t0.addingTimeInterval(30 * 60)
        engine.startNextPhase(now: next)
        #expect(engine.phase == .shortBreak)
        #expect(engine.status == .running(endDate: next.addingTimeInterval(5 * 60)))
    }

    @Test func autoStartChainsPhases() {
        var engine = pomodoro(autoStart: true)
        engine.startPomodoro(now: t0)
        let end = t0.addingTimeInterval(25 * 60)

        let completion = engine.tick(now: end)

        #expect(completion?.didAutoStartNext == true)
        #expect(engine.phase == .shortBreak)
        #expect(engine.status == .running(endDate: end.addingTimeInterval(5 * 60)))
    }

    @Test func longBreakFollowsEveryNthWorkSession() {
        var engine = pomodoro(work: 1, short: 1, long: 2, sessions: 3, autoStart: true)
        var now = t0
        engine.startPomodoro(now: now)

        var phases: [TimerPhase] = [engine.phase]
        for _ in 0..<7 {
            now = now.addingTimeInterval(engine.phaseDuration)
            engine.tick(now: now)
            phases.append(engine.phase)
        }

        #expect(phases == [.work, .shortBreak, .work, .shortBreak, .work, .longBreak, .work, .shortBreak])
        #expect(engine.completedWorkSessions == 4)
    }

    @Test func sessionDotsFillDuringLongBreakAndResetAfter() {
        var engine = pomodoro(sessions: 2, autoStart: true)
        var now = t0
        engine.startPomodoro(now: now)
        #expect(engine.completedSessionsInCycle == 0)

        for _ in 0..<3 {  // work, short, work → long break
            now = now.addingTimeInterval(engine.phaseDuration)
            engine.tick(now: now)
        }
        #expect(engine.phase == .longBreak)
        #expect(engine.completedSessionsInCycle == 2)

        now = now.addingTimeInterval(engine.phaseDuration)
        engine.tick(now: now)
        #expect(engine.phase == .work)
        #expect(engine.completedSessionsInCycle == 0)
    }

    @Test func skipCountsWorkAndStartsNextImmediately() {
        var engine = pomodoro(sessions: 1)
        engine.startPomodoro(now: t0)
        let skipAt = t0.addingTimeInterval(60)

        let completion = engine.skipPhase(now: skipAt)

        #expect(completion?.nextPhase == .longBreak)
        #expect(engine.phase == .longBreak)
        #expect(engine.status == .running(endDate: skipAt.addingTimeInterval(15 * 60)))
        #expect(engine.completedWorkSessions == 1)
    }

    @Test func skipFromFinishedStartsUpcomingPhase() {
        var engine = pomodoro()
        engine.startPomodoro(now: t0)
        engine.tick(now: t0.addingTimeInterval(25 * 60))

        engine.skipPhase(now: t0.addingTimeInterval(26 * 60))

        #expect(engine.phase == .shortBreak)
        #expect(engine.completedWorkSessions == 1)
    }

    @Test func skipWhilePausedWorks() {
        var engine = pomodoro()
        engine.startPomodoro(now: t0)
        engine.pause(now: t0.addingTimeInterval(10))
        engine.skipPhase(now: t0.addingTimeInterval(20))
        #expect(engine.phase == .shortBreak)
        #expect(engine.status == .running(endDate: t0.addingTimeInterval(20 + 5 * 60)))
    }

    @Test func settingsChangeAppliesToNextPhaseOnly() {
        var engine = pomodoro()
        engine.startPomodoro(now: t0)
        engine.settings.shortBreakMinutes = 10

        #expect(engine.phaseDuration == 25 * 60)
        engine.skipPhase(now: t0)
        #expect(engine.phaseDuration == 10 * 60)
    }

    @Test func engineClampsSettings() {
        var engine = pomodoro(sessions: 0)
        #expect(engine.settings.sessionsBeforeLongBreak == PomodoroSettings.sessionsRange.lowerBound)
        engine.settings.workMinutes = 10_000
        #expect(engine.settings.workMinutes == PomodoroSettings.workMinutesRange.upperBound)
    }
}
