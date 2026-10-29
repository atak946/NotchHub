import Testing
@testable import NotchHub

struct AlertCountdownTests {
    private let start = ContinuousClock.now

    @Test func drainsLinearly() {
        let countdown = AlertCountdown.started(total: .seconds(6), at: start)

        #expect(countdown.fraction(at: start) == 1)
        #expect(abs(countdown.fraction(at: start.advanced(by: .seconds(3))) - 0.5) < 0.0001)
        #expect(countdown.fraction(at: start.advanced(by: .seconds(9))) == 0)
        #expect(countdown.remaining(at: start.advanced(by: .seconds(9))) == .zero)
    }

    @Test func pauseFreezesRemainingTime() {
        let paused = AlertCountdown.started(total: .seconds(6), at: start)
            .paused(at: start.advanced(by: .seconds(2)))

        #expect(!paused.isRunning)
        #expect(paused.remaining(at: start.advanced(by: .seconds(30))) == .seconds(4))
    }

    @Test func resumeContinuesFromPausedTime() {
        let resumeAt = start.advanced(by: .seconds(10))
        let resumed = AlertCountdown.started(total: .seconds(6), at: start)
            .paused(at: start.advanced(by: .seconds(1)))
            .resumed(at: resumeAt)

        #expect(resumed.isRunning)
        #expect(resumed.remaining(at: resumeAt.advanced(by: .seconds(1))) == .seconds(4))
    }

    @Test func resumeKeepsMinimumRemainingTime() {
        let resumeAt = start.advanced(by: .seconds(20))
        let resumed = AlertCountdown.started(total: .seconds(6), at: start)
            .paused(at: start.advanced(by: .milliseconds(5900)))
            .resumed(at: resumeAt)

        #expect(resumed.remaining(at: resumeAt) == AlertCountdown.minimumRemainingAfterResume)
    }

    @Test func pausingTwiceIsIdempotent() {
        let once = AlertCountdown.started(total: .seconds(6), at: start).paused(at: start.advanced(by: .seconds(1)))

        #expect(once.paused(at: start.advanced(by: .seconds(5))) == once)
    }

    @Test func zeroTotalReportsEmpty() {
        #expect(AlertCountdown.started(total: .zero, at: start).fraction(at: start) == 0)
    }
}
