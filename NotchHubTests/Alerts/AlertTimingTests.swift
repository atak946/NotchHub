import Testing
@testable import NotchHub

struct AlertTimingTests {
    @Test func standardScaleKeepsTheBaseDuration() {
        #expect(AlertTiming.duration(base: .seconds(6), scale: 1, queuedCount: 0, pulses: false) == .seconds(6))
    }

    @Test func scaleNeverGoesBelowTheMinimum() {
        #expect(AlertTiming.duration(base: .seconds(6), scale: 0.1, queuedCount: 0, pulses: false)
            == AlertTiming.minimumDuration)
    }

    @Test func alertsShorterThanTheMinimumKeepTheirOwnLength() {
        #expect(AlertTiming.duration(base: .milliseconds(1500), scale: 0.6, queuedCount: 0, pulses: false)
            == .milliseconds(1500))
    }

    @Test func busyQueueHalvesNonPulsingAlerts() {
        let busy = AlertTiming.busyQueueThreshold
        #expect(AlertTiming.duration(base: .seconds(12), scale: 1, queuedCount: busy, pulses: false) == .seconds(6))
        #expect(AlertTiming.duration(base: .seconds(12), scale: 1, queuedCount: busy - 1, pulses: false) == .seconds(12))
    }

    @Test func busyQueueSparesPulsingAlerts() {
        #expect(AlertTiming.duration(base: .seconds(30), scale: 1, queuedCount: 5, pulses: true) == .seconds(30))
    }

    @Test func coalescedChainGetsFullDurationEarlyOn() {
        #expect(AlertTiming.coalescedDuration(total: .seconds(6), elapsedInChain: .seconds(3)) == .seconds(6))
    }

    @Test func coalescedChainIsCutAtItsLifetime() {
        #expect(AlertTiming.coalescedDuration(total: .seconds(6), elapsedInChain: .seconds(17)) == .seconds(3))
        #expect(AlertTiming.coalescedDuration(total: .seconds(6), elapsedInChain: .seconds(60))
            == AlertCountdown.minimumRemainingAfterResume)
    }

    @Test func longAlertsSetTheirOwnChainLifetime() {
        #expect(AlertTiming.coalescedDuration(total: .seconds(30), elapsedInChain: .seconds(10)) == .seconds(20))
    }
}
