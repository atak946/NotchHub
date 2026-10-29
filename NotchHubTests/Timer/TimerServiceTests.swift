import Foundation
import Testing
@testable import NotchHub

@MainActor
struct TimerServiceTests {
    private let defaults = makeTimerTestDefaults()
    private let clock = FakeTimerClock()
    private let notifier = FakeTimerNotifier()

    private func makeService() -> TimerService {
        TimerService(defaults: defaults, clock: clock, notifier: notifier)
    }

    @Test func presetsAreFixed() {
        #expect(TimerService.presets == [300, 900, 1500, 2700])
    }

    @Test func startsIdleWithoutTouchingPermissions() {
        let service = makeService()
        #expect(service.state == .idle)
        #expect(service.remaining == 0)
        #expect(service.progress == 0)
        #expect(!service.hasCompactContent)
        #expect(notifier.prepareCount == 0)
    }

    @Test func startPreparesNotifierAndRuns() {
        let service = makeService()
        service.start(duration: 120)

        #expect(notifier.prepareCount == 1)
        #expect(service.state == .running(.countdown))
        #expect(service.remaining == 120)
        #expect(service.hasCompactContent)
    }

    @Test func refreshUpdatesRemainingAndProgress() {
        let service = makeService()
        service.start(duration: 100)
        clock.advance(by: 25)
        service.refresh()

        #expect(service.remaining == 75)
        #expect(service.progress == 0.25)
    }

    @Test func finishNotifiesAndCallsBack() {
        let service = makeService()
        var finishCalls = 0
        service.onFinish = { finishCalls += 1 }
        service.start(duration: 60)

        clock.advance(by: 61)
        service.refresh()
        service.refresh()

        #expect(service.state == .finished(.countdown))
        #expect(service.progress == 1)
        #expect(!service.hasCompactContent)
        #expect(finishCalls == 1)
        #expect(service.finishCount == 1)
        #expect(notifier.completions == [TimerCompletion(finishedPhase: .countdown, nextPhase: nil, didAutoStartNext: false)])
    }

    @Test func pausePreservesRemainingAcrossClockJump() {
        let service = makeService()
        service.start(duration: 300)
        clock.advance(by: 60)
        service.pause()

        clock.advance(by: 3 * 3600)  // e.g. machine slept for hours
        service.refresh()
        #expect(service.state == .paused(.countdown))
        #expect(service.remaining == 240)
        #expect(service.hasCompactContent)

        service.resume()
        clock.advance(by: 40)
        service.refresh()
        #expect(service.state == .running(.countdown))
        #expect(service.remaining == 200)
        #expect(notifier.completions.isEmpty)
    }

    @Test func runningTimerCatchesUpAfterSleep() {
        let service = makeService()
        service.start(duration: 300)
        clock.advance(by: 3600)
        service.refresh()
        #expect(service.state == .finished(.countdown))
    }

    @Test func cancelReturnsToIdle() {
        let service = makeService()
        service.startPomodoro()
        service.cancel()
        #expect(service.state == .idle)
        #expect(!service.isPomodoro)
        #expect(service.remaining == 0)
    }

    @Test func pomodoroFlowUsesSettingsAndSkip() {
        let service = makeService()
        service.pomodoroSettings.workMinutes = 30
        service.startPomodoro()

        #expect(service.state == .running(.work))
        #expect(service.remaining == 30 * 60)
        #expect(service.upcomingPhase == .shortBreak)

        service.skipPhase()
        #expect(service.state == .running(.shortBreak))
        #expect(service.completedSessionsInCycle == 1)
        #expect(notifier.completions.isEmpty)
    }

    @Test func pomodoroFinishWaitsThenStartsNextPhase() {
        let service = makeService()
        service.startPomodoro()
        clock.advance(by: 25 * 60)
        service.refresh()

        #expect(service.state == .finished(.work))
        #expect(notifier.completions.last?.nextPhase == .shortBreak)

        service.startNextPhase()
        #expect(service.state == .running(.shortBreak))
        #expect(service.remaining == 5 * 60)
    }

    @Test func customMinutesStartsTimer() {
        let service = makeService()
        service.customMinutes = 7
        service.startCustom()
        #expect(service.remaining == 7 * 60)
    }

    // MARK: Persistence

    @Test func providesDefaultSettings() {
        let service = makeService()
        #expect(service.pomodoroSettings == .default)
        #expect(service.customMinutes == TimerService.defaultCustomMinutes)
    }

    @Test func persistsSettingsAcrossInstances() {
        let service = makeService()
        service.pomodoroSettings = PomodoroSettings(
            workMinutes: 50,
            shortBreakMinutes: 10,
            longBreakMinutes: 30,
            sessionsBeforeLongBreak: 3,
            autoStartNextPhase: true
        )
        service.customMinutes = 42

        let reloaded = makeService()
        #expect(reloaded.pomodoroSettings.workMinutes == 50)
        #expect(reloaded.pomodoroSettings.shortBreakMinutes == 10)
        #expect(reloaded.pomodoroSettings.longBreakMinutes == 30)
        #expect(reloaded.pomodoroSettings.sessionsBeforeLongBreak == 3)
        #expect(reloaded.pomodoroSettings.autoStartNextPhase)
        #expect(reloaded.customMinutes == 42)
        #expect(reloaded.sessionsBeforeLongBreak == 3)
    }

    @Test func clampsAssignedSettings() {
        let service = makeService()
        service.pomodoroSettings.workMinutes = 0
        service.pomodoroSettings.longBreakMinutes = 999
        service.pomodoroSettings.sessionsBeforeLongBreak = -3
        service.customMinutes = 10_000

        #expect(service.pomodoroSettings.workMinutes == PomodoroSettings.workMinutesRange.lowerBound)
        #expect(service.pomodoroSettings.longBreakMinutes == PomodoroSettings.longBreakMinutesRange.upperBound)
        #expect(service.pomodoroSettings.sessionsBeforeLongBreak == PomodoroSettings.sessionsRange.lowerBound)
        #expect(service.customMinutes == TimerService.customMinutesRange.upperBound)
        #expect(defaults.integer(forKey: "Timer.workMinutes") == PomodoroSettings.workMinutesRange.lowerBound)
    }

    @Test func clampsInvalidStoredSettings() {
        defaults.set(500, forKey: "Timer.workMinutes")
        defaults.set(0, forKey: "Timer.shortBreakMinutes")
        defaults.set(99, forKey: "Timer.sessionsBeforeLongBreak")
        defaults.set("bogus", forKey: "Timer.longBreakMinutes")
        defaults.set(-1, forKey: "Timer.customMinutes")

        let service = makeService()

        #expect(service.pomodoroSettings.workMinutes == PomodoroSettings.workMinutesRange.upperBound)
        #expect(service.pomodoroSettings.shortBreakMinutes == PomodoroSettings.shortBreakMinutesRange.lowerBound)
        #expect(service.pomodoroSettings.sessionsBeforeLongBreak == PomodoroSettings.sessionsRange.upperBound)
        #expect(service.pomodoroSettings.longBreakMinutes == PomodoroSettings.default.longBreakMinutes)
        #expect(service.customMinutes == TimerService.customMinutesRange.lowerBound)
    }
}
