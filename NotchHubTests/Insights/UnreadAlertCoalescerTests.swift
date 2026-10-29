import Foundation
import Testing
@testable import NotchHub

struct UnreadAlertCoalescerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func firstPollIsBaselineOnly() {
        var coalescer = UnreadAlertCoalescer()
        #expect(coalescer.evaluate(previous: nil, current: ["WhatsApp": 5], at: start).isEmpty)
    }

    @Test func increaseAlertsWithDelta() {
        var coalescer = UnreadAlertCoalescer()
        let result = coalescer.evaluate(previous: ["WhatsApp": 2, "Mail": 1], current: ["WhatsApp": 5, "Mail": 1], at: start)
        #expect(result == [UnreadIncrease(app: "WhatsApp", count: 5, newMessages: 3)])
    }

    @Test func decreaseAndUnchangedDoNotAlert() {
        var coalescer = UnreadAlertCoalescer()
        #expect(coalescer.evaluate(previous: ["Slack": 4], current: ["Slack": 1], at: start).isEmpty)
        #expect(coalescer.evaluate(previous: ["Slack": 1], current: ["Slack": 1], at: start).isEmpty)
    }

    @Test func increasesWithinWindowAccumulate() {
        var coalescer = UnreadAlertCoalescer()
        _ = coalescer.evaluate(previous: ["WhatsApp": 0], current: ["WhatsApp": 1], at: start)
        let second = coalescer.evaluate(previous: ["WhatsApp": 1], current: ["WhatsApp": 3], at: start.addingTimeInterval(3))
        #expect(second == [UnreadIncrease(app: "WhatsApp", count: 3, newMessages: 3)])
    }

    @Test func increasesAfterWindowStartNewBurst() {
        var coalescer = UnreadAlertCoalescer()
        _ = coalescer.evaluate(previous: ["WhatsApp": 0], current: ["WhatsApp": 1], at: start)
        let later = coalescer.evaluate(
            previous: ["WhatsApp": 1], current: ["WhatsApp": 2], at: start.addingTimeInterval(UnreadAlertCoalescer.window)
        )
        #expect(later == [UnreadIncrease(app: "WhatsApp", count: 2, newMessages: 1)])
    }

    @Test func burstsArePerApp() {
        var coalescer = UnreadAlertCoalescer()
        _ = coalescer.evaluate(previous: ["A": 0, "B": 0], current: ["A": 2, "B": 0], at: start)
        let result = coalescer.evaluate(previous: ["A": 2, "B": 0], current: ["A": 2, "B": 1], at: start.addingTimeInterval(1))
        #expect(result == [UnreadIncrease(app: "B", count: 1, newMessages: 1)])
    }

    @Test func readingResetsBurst() {
        var coalescer = UnreadAlertCoalescer()
        _ = coalescer.evaluate(previous: ["A": 0], current: ["A": 3], at: start)
        _ = coalescer.evaluate(previous: ["A": 3], current: ["A": 0], at: start.addingTimeInterval(1))
        let result = coalescer.evaluate(previous: ["A": 0], current: ["A": 1], at: start.addingTimeInterval(2))
        #expect(result == [UnreadIncrease(app: "A", count: 1, newMessages: 1)])
    }
}
