import Foundation
import Testing
@testable import NotchHub

struct EnergyPolicyTests {
    // MARK: - Notification mirror

    @Test func mirrorPollStaysFastWithoutObserverOrWithBanner() {
        #expect(NotificationMirrorPollPolicy.delay(
            isTrusted: true, hasBannerWindow: false, isObserverAttached: false, quietPolls: 100
        ) == .seconds(1))
        #expect(NotificationMirrorPollPolicy.delay(
            isTrusted: true, hasBannerWindow: true, isObserverAttached: true, quietPolls: 100
        ) == .milliseconds(250))
        #expect(NotificationMirrorPollPolicy.delay(
            isTrusted: false, hasBannerWindow: true, isObserverAttached: true, quietPolls: 0
        ) == .seconds(10))
    }

    @Test func mirrorPollBacksOffWhileObserverIsAttached() {
        let delays = [0, 5, 6, 7, 8, 50].map {
            NotificationMirrorPollPolicy.delay(isTrusted: true, hasBannerWindow: false, isObserverAttached: true, quietPolls: $0)
        }
        #expect(delays == [.seconds(1), .seconds(1), .seconds(2), .seconds(4), .seconds(4), .seconds(4)])
    }

    // MARK: - Media

    @Test func mediaPollFollowsPlayerState() {
        #expect(MediaPollPolicy.interval(anyPlayerRunning: false, isPlaying: false) == .seconds(30))
        #expect(MediaPollPolicy.interval(anyPlayerRunning: true, isPlaying: false) == .seconds(15))
        #expect(MediaPollPolicy.interval(anyPlayerRunning: true, isPlaying: true) == .seconds(5))
    }

    // MARK: - Meeting

    @Test func meetingPollsOnlyWithMicrophone() {
        #expect(MeetingPollPolicy.needsPolling(micInUse: true))
        #expect(!MeetingPollPolicy.needsPolling(micInUse: false))
    }

    // MARK: - Capture pump

    @Test func capturePumpBacksOffAfterGrace() {
        #expect(CaptureCatcherService.pumpDelay(idlePumps: 0) == .milliseconds(500))
        #expect(CaptureCatcherService.pumpDelay(idlePumps: 8) == .milliseconds(500))
        #expect(CaptureCatcherService.pumpDelay(idlePumps: 9) == .seconds(1))
        #expect(CaptureCatcherService.pumpDelay(idlePumps: 100) == .seconds(5))
    }
}
