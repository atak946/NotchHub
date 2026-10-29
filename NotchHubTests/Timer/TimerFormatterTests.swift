import Foundation
import Testing
@testable import NotchHub

struct TimerFormatterTests {
    @Test(arguments: [
        (0.0, "0:00"),
        (-5.0, "0:00"),
        (0.2, "0:01"),
        (59.0, "0:59"),
        (245.0, "4:05"),
        (1500.0, "25:00"),
        (3723.0, "1:02:03"),
    ])
    func clock(remaining: TimeInterval, expected: String) {
        #expect(TimerFormatter.clock(remaining) == expected)
    }

    @Test(arguments: [
        (0.0, "0:00"),
        (5.0, "0:05"),
        (599.0, "9:59"),
        (599.4, "10dk"),
        (600.0, "10dk"),
        (724.0, "13dk"),
        (3599.0, "60dk"),
        (3600.0, "1sa"),
        (7300.0, "2sa"),
        (Double.infinity, "0:00"),
    ])
    func compact(remaining: TimeInterval, expected: String) {
        #expect(TimerFormatter.compact(remaining) == expected)
    }

    @Test func minutesLabel() {
        #expect(TimerFormatter.minutesLabel(900) == "15 dk")
    }

    @Test func notificationCopy() {
        #expect(UserNotificationTimerNotifier.title(for: .work) == "Odak oturumu tamamlandı")
        #expect(UserNotificationTimerNotifier.body(
            for: TimerCompletion(finishedPhase: .work, nextPhase: .longBreak, didAutoStartNext: true)
        ) == "Uzun Mola başladı.")
        #expect(UserNotificationTimerNotifier.body(
            for: TimerCompletion(finishedPhase: .countdown, nextPhase: nil, didAutoStartNext: false)
        ) == "Zamanlayıcın bitti.")
    }
}
