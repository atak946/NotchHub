import Foundation
import Testing
@testable import NotchHub

struct MeetingDetectionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000)
    private let link = MeetingLink(provider: .teams, url: URL(fileURLWithPath: "/meet"))

    @Test func requiresMicrophone() {
        #expect(MeetingDetector.source(micInUse: false, meetingApps: [.zoom], calendarMeeting: nil) == nil)
        #expect(MeetingDetector.source(micInUse: true, meetingApps: [], calendarMeeting: nil) == nil)
        #expect(MeetingDetector.source(micInUse: true, meetingApps: [.zoom], calendarMeeting: nil) == "Zoom")
    }

    @Test func calendarMeetingWithLinkInProgressCounts() {
        let inProgress = CalendarEvent(
            id: "1", title: "Standup", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(600),
            meetingLink: link
        )
        let noLink = CalendarEvent(id: "2", title: "Focus", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(600))
        let later = CalendarEvent(
            id: "3", title: "Later", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200), meetingLink: link
        )

        let found = MeetingDetector.calendarMeeting(in: [noLink, later, inProgress], at: now)
        #expect(found?.id == "1")
        #expect(MeetingDetector.calendarMeeting(in: [noLink, later], at: now) == nil)
        #expect(MeetingDetector.source(micInUse: true, meetingApps: [], calendarMeeting: found) == "Standup")
    }

    @Test func browsersAreNotMeetingApps() {
        let apps = [
            SystemRunningApp(bundleIdentifier: "com.google.Chrome", name: "Chrome"),
            SystemRunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari"),
        ]
        #expect(MeetingAppCatalog.running(in: apps).isEmpty)
    }

    @Test func knownMeetingAppsAreFound() {
        let apps = [
            SystemRunningApp(bundleIdentifier: "com.microsoft.teams2", name: "Microsoft Teams"),
            SystemRunningApp(bundleIdentifier: "us.zoom.xos", name: "zoom.us"),
            SystemRunningApp(bundleIdentifier: nil, name: "daemon"),
        ]
        #expect(MeetingAppCatalog.running(in: apps).map(\.name) == ["Zoom", "Teams"])
    }

    @Test func mediaPolicy() {
        #expect(MeetingMediaPolicy.shouldPauseOnEnter(autoPause: true, isPlaying: true))
        #expect(!MeetingMediaPolicy.shouldPauseOnEnter(autoPause: true, isPlaying: false))
        #expect(!MeetingMediaPolicy.shouldPauseOnEnter(autoPause: false, isPlaying: true))
        #expect(MeetingMediaPolicy.shouldResumeOnExit(didPause: true, isPlaying: false))
        #expect(!MeetingMediaPolicy.shouldResumeOnExit(didPause: true, isPlaying: true))
        #expect(!MeetingMediaPolicy.shouldResumeOnExit(didPause: false, isPlaying: false))
    }
}

@MainActor
struct MeetingModeControllerTests {
    private let clock = SystemTestClock()
    private let inputs = SystemTestMeetingInputs()

    private func makeController(media: SystemTestMedia, autoPause: Bool = true) -> MeetingModeController {
        let controller = MeetingModeController(
            inputs: inputs, media: media, clock: clock, defaults: SystemTestSupport.makeDefaults()
        )
        controller.autoPauseMusic = autoPause
        controller.start()
        return controller
    }

    private func enterMeeting(_ controller: MeetingModeController) {
        inputs.isMicrophoneInUse = true
        inputs.runningMeetingApps = [.zoom]
        controller.evaluate()
        clock.advance(by: MeetingModeController.debounceInterval)
        controller.settle()
    }

    private func leaveMeeting(_ controller: MeetingModeController) {
        inputs.isMicrophoneInUse = false
        controller.evaluate()
        clock.advance(by: MeetingModeController.debounceInterval)
        controller.settle()
    }

    @Test func entersAfterDebounceAndTracksElapsed() {
        let controller = makeController(media: SystemTestMedia(isPlaying: false))
        let detectedAt = clock.now
        inputs.isMicrophoneInUse = true
        inputs.runningMeetingApps = [.zoom]

        controller.evaluate()
        #expect(!controller.isInMeeting)

        clock.advance(by: MeetingModeController.debounceInterval)
        controller.settle()

        #expect(controller.session == MeetingSession(start: detectedAt, source: "Zoom"))
        #expect(controller.hasCompactIndicator)
        #expect(controller.elapsed(at: detectedAt.addingTimeInterval(65)) == 65)
    }

    @Test func pausesPlayingMusicAndResumesOnExit() {
        let media = SystemTestMedia(isPlaying: true)
        let controller = makeController(media: media)

        enterMeeting(controller)
        #expect(media.playPauseCount == 1)
        #expect(!media.isMediaPlaying)
        #expect(controller.didPauseMedia)

        leaveMeeting(controller)
        #expect(!controller.isInMeeting)
        #expect(media.playPauseCount == 2)
        #expect(media.isMediaPlaying)
    }

    @Test func doesNotTouchMusicThatWasNotPlaying() {
        let media = SystemTestMedia(isPlaying: false)
        let controller = makeController(media: media)

        enterMeeting(controller)
        leaveMeeting(controller)

        #expect(media.playPauseCount == 0)
    }

    @Test func doesNotPauseWhenAutoPauseIsOff() {
        let media = SystemTestMedia(isPlaying: true)
        let controller = makeController(media: media, autoPause: false)

        enterMeeting(controller)
        leaveMeeting(controller)

        #expect(media.playPauseCount == 0)
        #expect(media.isMediaPlaying)
    }

    @Test func doesNotResumeWhenUserAlreadyResumed() {
        let media = SystemTestMedia(isPlaying: true)
        let controller = makeController(media: media)
        enterMeeting(controller)

        media.isMediaPlaying = true
        leaveMeeting(controller)

        #expect(media.playPauseCount == 1)
        #expect(media.isMediaPlaying)
    }

    @Test func briefMicDropDoesNotEndMeeting() {
        let controller = makeController(media: SystemTestMedia(isPlaying: false))
        enterMeeting(controller)

        inputs.isMicrophoneInUse = false
        controller.evaluate()
        clock.advance(by: 1)
        inputs.isMicrophoneInUse = true
        controller.evaluate()
        clock.advance(by: MeetingModeController.debounceInterval)
        controller.settle()

        #expect(controller.isInMeeting)
    }

    @Test func calendarMeetingWithoutAppCounts() {
        let controller = makeController(media: SystemTestMedia(isPlaying: false))
        let now = clock.now
        inputs.calendarEvents = [CalendarEvent(
            id: "e", title: "Sprint review",
            start: now.addingTimeInterval(-60), end: now.addingTimeInterval(3600),
            meetingLink: MeetingLink(provider: .meet, url: URL(fileURLWithPath: "/meet"))
        )]
        inputs.isMicrophoneInUse = true

        controller.evaluate()
        clock.advance(by: MeetingModeController.debounceInterval)
        controller.settle()

        #expect(controller.session?.source == "Sprint review")
    }

    @Test func disablingEndsMeetingAndResumesMusic() {
        let media = SystemTestMedia(isPlaying: true)
        let controller = makeController(media: media)
        enterMeeting(controller)

        controller.isEnabled = false

        #expect(!controller.isInMeeting)
        #expect(media.isMediaPlaying)
        #expect(media.playPauseCount == 2)
    }

    @Test func stopIsIdempotent() {
        let controller = makeController(media: SystemTestMedia(isPlaying: false))
        enterMeeting(controller)

        controller.stop()
        controller.stop()

        #expect(!controller.isInMeeting)
        #expect(!controller.isMonitoring)
    }
}
