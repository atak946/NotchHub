import Foundation
import Testing
@testable import NotchHub

struct RelativeTimeFormatterTests {
    private typealias F = CalendarFixtures
    private let event = F.event("e", start: F.date(hour: 10), minutes: 60)

    @Test(arguments: [
        (F.date(hour: 9, minute: 45), "15 dk sonra"),
        (F.date(hour: 9, minute: 59, second: 30), "1 dk sonra"),
        (F.date(hour: 8, minute: 40), "1 sa 20 dk sonra"),
        (F.date(hour: 8), "2 sa sonra"),
        (F.date(hour: 10), "şimdi"),
        (F.date(hour: 10, second: 30), "şimdi"),
        (F.date(hour: 10, minute: 50), "10 dk içinde biter"),
        (F.date(hour: 10, minute: 1), "59 dk içinde biter"),
        (F.date(hour: 11), "bitti"),
    ])
    func formats(date: Date, expected: String) {
        #expect(RelativeTimeFormatter.text(for: event, at: date) == expected)
    }

    @Test func durationRoundsUpToWholeMinutes() {
        #expect(RelativeTimeFormatter.duration(1) == "1 dk")
        #expect(RelativeTimeFormatter.duration(61) == "2 dk")
        #expect(RelativeTimeFormatter.duration(3_600) == "1 sa")
        #expect(RelativeTimeFormatter.duration(3_660) == "1 sa 1 dk")
    }

    @Test func settingsLeadTimeTitles() {
        #expect(CalendarSettingsSection.title(forLeadTime: 0) == "Kapalı")
        #expect(CalendarSettingsSection.title(forLeadTime: 60) == "1 dakika önce")
        #expect(CalendarSettingsSection.title(forLeadTime: 600) == "10 dakika önce")
    }
}
