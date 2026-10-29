import Foundation

/// What meeting mode reads to decide whether the user is in a meeting.
@MainActor
protocol MeetingModeInputs: AnyObject {
    var isMicrophoneInUse: Bool { get }
    var runningMeetingApps: [MeetingApp] { get }
    /// Calendar events that may be in progress (next event + rest of today).
    var calendarEvents: [CalendarEvent] { get }
}

/// Playback control meeting mode needs. `MediaService` conforms.
@MainActor
protocol MeetingMediaControlling: AnyObject {
    var isMediaPlaying: Bool { get }
    func playPause()
}

extension MediaService: MeetingMediaControlling {
    var isMediaPlaying: Bool { nowPlaying?.isPlaying ?? false }
}

/// A detected meeting.
struct MeetingSession: Equatable, Sendable {
    let start: Date
    /// "Zoom", "Teams" or the calendar event title.
    let source: String
}

enum MeetingDetector {
    /// A timed, in-progress event with a meeting link.
    static func calendarMeeting(in events: [CalendarEvent], at date: Date) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.meetingLink != nil && $0.isInProgress(at: date) }
    }

    /// Meeting = microphone in use AND (a meeting app is running OR a calendar meeting is in progress).
    static func source(micInUse: Bool, meetingApps: [MeetingApp], calendarMeeting: CalendarEvent?) -> String? {
        guard micInUse else { return nil }
        if let app = meetingApps.first { return app.name }
        return calendarMeeting.map(\.title)
    }
}

/// Pause on enter only if music was playing; resume on exit only if we paused it and it is still paused.
enum MeetingMediaPolicy {
    static func shouldPauseOnEnter(autoPause: Bool, isPlaying: Bool) -> Bool {
        autoPause && isPlaying
    }

    static func shouldResumeOnExit(didPause: Bool, isPlaying: Bool) -> Bool {
        didPause && !isPlaying
    }
}

/// Time alone can only change the meeting state while the microphone is on (a calendar meeting starting
/// or ending); otherwise the observed inputs (mic, apps, events) drive every change.
enum MeetingPollPolicy {
    static func needsPolling(micInUse: Bool) -> Bool {
        micInUse
    }
}
