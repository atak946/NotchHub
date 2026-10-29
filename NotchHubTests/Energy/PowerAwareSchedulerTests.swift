import Foundation
import Testing
@testable import NotchHub

struct PowerAwareSchedulerTests {
    private static let away = PowerConditions(isScreenAsleep: true)
    private static let locked = PowerConditions(isSessionInactive: true)
    private static let lowPower = PowerConditions(isLowPowerMode: true)

    @Test func nominalConditionsKeepTheBase() {
        for priority in [PollingPriority.standard, .awayOnly, .critical] {
            #expect(PowerAwareScheduler.interval(.seconds(5), conditions: .nominal, priority: priority) == .seconds(5))
        }
    }

    @Test func lowPowerModeDoublesOnlyStandardWork() {
        #expect(PowerAwareScheduler.interval(.seconds(5), conditions: Self.lowPower, priority: .standard) == .seconds(10))
        #expect(PowerAwareScheduler.interval(.seconds(5), conditions: Self.lowPower, priority: .awayOnly) == .seconds(5))
        #expect(PowerAwareScheduler.interval(.seconds(5), conditions: Self.lowPower, priority: .critical) == .seconds(5))
    }

    @Test func awaySlowsEverythingButCriticalWork() {
        #expect(PowerAwareScheduler.interval(.seconds(15), conditions: Self.away, priority: .standard) == .seconds(60))
        #expect(PowerAwareScheduler.interval(.seconds(15), conditions: Self.locked, priority: .awayOnly) == .seconds(60))
        #expect(PowerAwareScheduler.interval(.seconds(5), conditions: Self.away, priority: .critical) == .seconds(5))
    }

    @Test func awayAndLowPowerCompound() {
        let both = PowerConditions(isLowPowerMode: true, isScreenAsleep: true)
        #expect(PowerAwareScheduler.interval(.seconds(10), conditions: both, priority: .standard) == .seconds(80))
    }

    @Test func awayScalingIsCappedButNeverShortensTheBase() {
        #expect(PowerAwareScheduler.interval(.seconds(120), conditions: Self.away, priority: .standard) == .seconds(300))
        #expect(PowerAwareScheduler.interval(.seconds(600), conditions: Self.away, priority: .standard) == .seconds(600))
    }

    @Test func zeroBaseStaysZero() {
        #expect(PowerAwareScheduler.interval(.zero, conditions: Self.away, priority: .standard) == .zero)
    }

    @Test func backoffDoublesAfterGraceAndCaps() {
        let delays = (0...6).map {
            PowerAwareScheduler.backoff(base: .seconds(1), maximum: .seconds(8), unchangedCount: $0, graceCount: 2)
        }
        #expect(delays == [.seconds(1), .seconds(1), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(8)])
    }

    @Test func backoffHandlesHugeCountsAndBadMaximum() {
        #expect(PowerAwareScheduler.backoff(base: .seconds(15), maximum: .seconds(60), unchangedCount: 10_000) == .seconds(60))
        #expect(PowerAwareScheduler.backoff(base: .seconds(15), maximum: .seconds(5), unchangedCount: 3) == .seconds(15))
        #expect(PowerAwareScheduler.backoff(base: .seconds(15), maximum: .seconds(60), unchangedCount: -1) == .seconds(15))
    }

    @Test func toleranceIsTenPercentCappedAtFiveSeconds() {
        func tolerance(_ seconds: Double) -> Double {
            PowerAwareScheduler.seconds(PowerAwareScheduler.tolerance(for: .seconds(seconds)))
        }
        #expect(abs(tolerance(1) - 0.1) < 1e-9)
        #expect(abs(tolerance(15) - 1.5) < 1e-9)
        #expect(tolerance(600) == 5)
        #expect(tolerance(-1) == 0)
    }

    @Test func secondsConvertsSubsecondDurations() {
        #expect(PowerAwareScheduler.seconds(.milliseconds(250)) == 0.25)
        #expect(PowerAwareScheduler.seconds(.seconds(90)) == 90)
    }

    @Test func resumeIsReturningOrLeavingLowPower() {
        #expect(PowerConditionsTransition.isResume(from: Self.away, to: .nominal))
        #expect(PowerConditionsTransition.isResume(from: Self.locked, to: .nominal))
        #expect(PowerConditionsTransition.isResume(from: Self.lowPower, to: .nominal))
        #expect(!PowerConditionsTransition.isResume(from: .nominal, to: Self.away))
        #expect(!PowerConditionsTransition.isResume(from: .nominal, to: Self.lowPower))
        let stillLocked = PowerConditions(isScreenAsleep: true, isSessionInactive: true)
        #expect(!PowerConditionsTransition.isResume(from: stillLocked, to: Self.locked))
    }
}
