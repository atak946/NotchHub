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

    @Test func browserTabsPollFasterAndWakeAtTheTrackEnd() {
        let web = { (remaining: TimeInterval?) in
            MediaPollPolicy.interval(anyPlayerRunning: true, isPlaying: true, hasPushEvents: false, remaining: remaining)
        }
        #expect(web(nil) == .seconds(2))
        #expect(web(120) == .seconds(2))
        // 1.2 s left: poll 0.6 s after the expected end.
        #expect(web(1.2) == .milliseconds(1800))
        // Right at the end it still waits the minimum, never spins.
        #expect(web(0.01) == .milliseconds(610))
        #expect(web(0) == .seconds(2))
        #expect(web(-3) == .seconds(2))
        #expect(web(.infinity) == .seconds(2))
        // Paused tabs keep the slow pace.
        #expect(MediaPollPolicy.interval(anyPlayerRunning: true, isPlaying: false, hasPushEvents: false, remaining: 1) == .seconds(15))
    }

    @Test func pushingPlayersIgnoreTheTrackEnd() {
        #expect(MediaPollPolicy.interval(anyPlayerRunning: true, isPlaying: true, hasPushEvents: true, remaining: 1) == .seconds(5))
    }

    @Test func onlyTrackKeyReleasesTriggerARead() {
        let next = (17 << 16) | (0xB << 8)
        #expect(MediaKeyChange.isTrackKeyUp(subtype: 8, data1: next))
        #expect(MediaKeyChange.isTrackKeyUp(subtype: 8, data1: (16 << 16) | (0xB << 8)))
        // Key-down, other subtypes and volume keys (0) do not.
        #expect(!MediaKeyChange.isTrackKeyUp(subtype: 8, data1: (17 << 16) | (0xA << 8)))
        #expect(!MediaKeyChange.isTrackKeyUp(subtype: 7, data1: next))
        #expect(!MediaKeyChange.isTrackKeyUp(subtype: 8, data1: (0 << 16) | (0xB << 8)))
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
