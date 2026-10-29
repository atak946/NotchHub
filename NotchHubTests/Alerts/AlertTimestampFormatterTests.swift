import Foundation
import Testing
@testable import NotchHub

struct AlertTimestampFormatterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private let posted = Date(timeIntervalSince1970: 1_800_000_000) // 08:00 UTC

    @Test func showsNowForTheFirstMinute() {
        let text = AlertTimestampFormatter.text(postedAt: posted, now: posted.addingTimeInterval(59), calendar: calendar)
        #expect(text == "şimdi")
    }

    @Test func showsMinutesWithinTheHour() {
        let text = AlertTimestampFormatter.text(postedAt: posted, now: posted.addingTimeInterval(5 * 60), calendar: calendar)
        #expect(text == "5 dk")
    }

    @Test func showsClockTimeAfterAnHour() {
        let text = AlertTimestampFormatter.text(postedAt: posted, now: posted.addingTimeInterval(2 * 3600), calendar: calendar)
        #expect(text == "08:00")
    }

    @Test func clockSkewCountsAsNow() {
        let text = AlertTimestampFormatter.text(postedAt: posted, now: posted.addingTimeInterval(-30), calendar: calendar)
        #expect(text == "şimdi")
    }
}
