import Foundation
import Testing
@testable import NotchHub

struct TimerTickPolicyTests {
    private static let margin = TimerTickPolicy.boundaryMargin
    private static let pomodoro: TimeInterval = 25 * 60

    @Test func secondsViewTicksOnTheNextWholeSecond() {
        let delay = TimerTickPolicy.delay(remaining: 100.3, phaseDuration: Self.pomodoro, showsSeconds: true)
        #expect(abs(delay - (0.3 + Self.margin)) < 1e-9)
        let onBoundary = TimerTickPolicy.delay(remaining: 100, phaseDuration: Self.pomodoro, showsSeconds: true)
        #expect(abs(onBoundary - (1 + Self.margin)) < 1e-9)
    }

    @Test func closedGlyphAboveTenMinutesWaitsForRingStepOrMinute() {
        // 20:00.5 left of 25:00: the text "21dk" → "20dk" changes in 0.5 s.
        let soon = TimerTickPolicy.delay(remaining: 1200.5, phaseDuration: Self.pomodoro, showsSeconds: false)
        #expect(abs(soon - (0.5 + Self.margin)) < 1e-9)
        // 19:30 left: text changes in 30 s, the ring step (1500 / 200 = 7.5 s) wins.
        let ring = TimerTickPolicy.delay(remaining: 1170, phaseDuration: Self.pomodoro, showsSeconds: false)
        #expect(abs(ring - 7.5) < 1e-9)
    }

    @Test func closedGlyphBelowTenMinutesTicksEverySecond() {
        let delay = TimerTickPolicy.delay(remaining: 300.4, phaseDuration: Self.pomodoro, showsSeconds: false)
        #expect(abs(delay - (0.4 + Self.margin)) < 1e-9)
    }

    @Test func compactChangePointsMatchTheFormatter() {
        for shown in [7200, 3601, 3600, 3599, 1201, 1200, 660, 601, 600, 599, 5, 1] {
            let next = TimerTickPolicy.nextCompactChange(fromShown: shown)
            #expect(next < shown)
            #expect(TimerFormatter.compact(TimeInterval(next)) != TimerFormatter.compact(TimeInterval(shown)))
            if next + 1 < shown {
                #expect(TimerFormatter.compact(TimeInterval(next + 1)) == TimerFormatter.compact(TimeInterval(shown)))
            }
        }
    }

    @Test func ringStepIsClamped() {
        let short = TimerTickPolicy.delay(remaining: 3 * 3600 - 10, phaseDuration: 3 * 3600, showsSeconds: false)
        #expect(short <= TimerTickPolicy.maxRingStep)
        let tiny = TimerTickPolicy.delay(remaining: 50, phaseDuration: 60, showsSeconds: false)
        #expect(tiny >= Self.margin && tiny <= 1 + Self.margin)
    }

    @Test func finishedOrInvalidRemainingFallsBackToOneSecond() {
        #expect(TimerTickPolicy.delay(remaining: 0, phaseDuration: 60, showsSeconds: false) == TimerTickPolicy.minRingStep)
        #expect(TimerTickPolicy.delay(remaining: .nan, phaseDuration: 60, showsSeconds: true) == TimerTickPolicy.minRingStep)
    }
}
