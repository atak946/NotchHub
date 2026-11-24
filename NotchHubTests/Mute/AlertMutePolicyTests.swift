import Foundation
import Testing
@testable import NotchHub

struct AlertMutePolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    private func reason(
        until: Date? = nil, meeting: Bool = false, focus: Bool = false, overrides: Bool = false
    ) -> AlertMuteReason? {
        AlertMutePolicy.reason(
            manualUntil: until, now: now, isInMeeting: meeting, isInFocus: focus, overridesAutomatic: overrides
        )
    }

    @Test func notMutedWithoutAReason() {
        #expect(reason() == nil)
    }

    @Test func manualMuteWinsUntilItExpires() {
        let end = now.addingTimeInterval(60)
        #expect(reason(until: end, meeting: true) == .manual(until: end))
        #expect(reason(until: now.addingTimeInterval(-1)) == nil)
    }

    @Test func meetingComesBeforeFocus() {
        #expect(reason(meeting: true, focus: true) == .meeting)
        #expect(reason(focus: true) == .focus)
    }

    @Test func overrideOnlyLiftsAutomaticMuting() {
        let end = now.addingTimeInterval(60)
        #expect(reason(meeting: true, focus: true, overrides: true) == nil)
        #expect(reason(until: end, overrides: true) == .manual(until: end))
    }

    @Test func everythingShowsWhileNotMuted() {
        for behavior in [AlertMuteBehavior.drop, .hold, .timeSensitive, .always] {
            #expect(AlertMutePolicy.shouldPresent(behavior, isMuted: false, allowsTimeSensitive: false))
        }
    }

    @Test func mutedShowsOnlyWhatMayPass() {
        #expect(!AlertMutePolicy.shouldPresent(.drop, isMuted: true, allowsTimeSensitive: true))
        #expect(!AlertMutePolicy.shouldPresent(.hold, isMuted: true, allowsTimeSensitive: true))
        #expect(AlertMutePolicy.shouldPresent(.timeSensitive, isMuted: true, allowsTimeSensitive: true))
        #expect(!AlertMutePolicy.shouldPresent(.timeSensitive, isMuted: true, allowsTimeSensitive: false))
        #expect(AlertMutePolicy.shouldPresent(.always, isMuted: true, allowsTimeSensitive: false))
    }

    @Test func summaryListsBusiestSourcesFirst() {
        let sources = ["Mail", "Chat", "Chat", "Code", "Chat", "Mail"]
        #expect(AlertMutePolicy.summary(of: sources, maxSources: 2) == "Chat 3 · Mail 2")
    }

    @Test func untilTomorrowEndsAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let end = AlertMuteDuration.untilTomorrow.end(from: now, calendar: calendar)
        #expect(end > now)
        #expect(calendar.startOfDay(for: end) == end)
        #expect(AlertMuteDuration.oneHour.end(from: now, calendar: calendar) == now.addingTimeInterval(3600))
        #expect(AlertMuteDuration.untilTurnedOff.end(from: now, calendar: calendar) == .distantFuture)
    }
}
