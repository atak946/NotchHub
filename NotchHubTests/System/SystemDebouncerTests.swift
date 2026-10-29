import Foundation
import Testing
@testable import NotchHub

struct SystemDebouncerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func firstObservationCommitsImmediately() {
        var debouncer = SystemDebouncer<Int>(holdInterval: 5)

        #expect(debouncer.observe(1, at: start) == 1)
        #expect(debouncer.stable == 1)
        #expect(debouncer.settleDate == nil)
    }

    @Test func changeCommitsOnlyAfterHoldInterval() {
        var debouncer = SystemDebouncer<Int>(holdInterval: 5)
        _ = debouncer.observe(1, at: start)

        #expect(debouncer.observe(2, at: start) == nil)
        #expect(debouncer.settleDate == start.addingTimeInterval(5))
        #expect(debouncer.settle(at: start.addingTimeInterval(4.9)) == nil)
        #expect(debouncer.settle(at: start.addingTimeInterval(5)) == 2)
        #expect(debouncer.stable == 2)
    }

    @Test func flapBackToStableCancelsPending() {
        var debouncer = SystemDebouncer<Int>(holdInterval: 5)
        _ = debouncer.observe(1, at: start)
        _ = debouncer.observe(2, at: start)

        #expect(debouncer.observe(1, at: start.addingTimeInterval(2)) == nil)
        #expect(debouncer.settle(at: start.addingTimeInterval(10)) == nil)
        #expect(debouncer.stable == 1)
    }

    @Test func newPendingValueRestartsHold() {
        var debouncer = SystemDebouncer<Int>(holdInterval: 5)
        _ = debouncer.observe(1, at: start)
        _ = debouncer.observe(2, at: start)

        _ = debouncer.observe(3, at: start.addingTimeInterval(3))

        #expect(debouncer.settle(at: start.addingTimeInterval(5)) == nil)
        #expect(debouncer.settle(at: start.addingTimeInterval(8)) == 3)
    }

    @Test func repeatedPendingSampleKeepsOriginalStart() {
        var debouncer = SystemDebouncer<Int>(holdInterval: 5)
        _ = debouncer.observe(1, at: start)
        _ = debouncer.observe(2, at: start)

        #expect(debouncer.observe(2, at: start.addingTimeInterval(5)) == 2)
    }

    @Test func resetForgetsBaseline() {
        var debouncer = SystemDebouncer<Int>(holdInterval: 5)
        _ = debouncer.observe(1, at: start)

        debouncer.reset()

        #expect(debouncer.observe(7, at: start) == 7)
    }

    @Test func elapsedFormatting() {
        #expect(SystemFormat.elapsed(0) == "00:00")
        #expect(SystemFormat.elapsed(65) == "01:05")
        #expect(SystemFormat.elapsed(3599) == "59:59")
        #expect(SystemFormat.elapsed(3661) == "1:01:01")
        #expect(SystemFormat.elapsed(-5) == "00:00")
    }
}
