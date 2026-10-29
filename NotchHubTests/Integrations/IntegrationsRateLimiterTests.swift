import Foundation
import Testing
@testable import NotchHub

struct IntegrationsRateLimiterTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func allowsBurstUpToCapacityThenDrops() {
        var limiter = IntegrationsRateLimiter(capacity: 10, window: 10)
        let allowed = (0..<15).filter { _ in limiter.allow(at: start) }.count
        #expect(allowed == 10)
    }

    @Test func refillsOneTokenPerSecondForTenPerTenSeconds() {
        var limiter = IntegrationsRateLimiter(capacity: 10, window: 10)
        for _ in 0..<10 { _ = limiter.allow(at: start) }
        let allowed1 = limiter.allow(at: start.addingTimeInterval(0.5))
        #expect(!allowed1)
        let allowed2 = limiter.allow(at: start.addingTimeInterval(1.0))
        #expect(allowed2)
        let allowed3 = limiter.allow(at: start.addingTimeInterval(1.1))
        #expect(!allowed3)
    }

    @Test func refillNeverExceedsCapacity() {
        var limiter = IntegrationsRateLimiter(capacity: 3, window: 3)
        _ = limiter.allow(at: start)
        let later = start.addingTimeInterval(3600)
        let allowed = (0..<10).filter { _ in limiter.allow(at: later) }.count
        #expect(allowed == 3)
    }

    @Test func clockGoingBackwardsDoesNotMintTokens() {
        var limiter = IntegrationsRateLimiter(capacity: 2, window: 2)
        _ = limiter.allow(at: start)
        _ = limiter.allow(at: start)
        let allowed4 = limiter.allow(at: start.addingTimeInterval(-100))
        #expect(!allowed4)
        let allowed5 = limiter.allow(at: start.addingTimeInterval(-99.5))
        #expect(!allowed5)
        let allowed6 = limiter.allow(at: start.addingTimeInterval(-99))
        #expect(allowed6)
    }

    @Test func sanitizesInvalidConfiguration() {
        var limiter = IntegrationsRateLimiter(capacity: 0, window: 0)
        #expect(limiter.capacity == 1)
        let allowed7 = limiter.allow(at: start)
        #expect(allowed7)
    }
}

struct IntegrationsLineBufferTests {
    @Test func splitsLinesAcrossChunks() throws {
        var buffer = IntegrationsLineBuffer(maxLineBytes: 100)
        #expect(try buffer.append(Data("{\"a\":1}\n{\"b\"".utf8)).get() == ["{\"a\":1}"])
        #expect(try buffer.append(Data(":2}\r\n\n  \n".utf8)).get() == ["{\"b\":2}"])
        #expect(buffer.flush() == nil)
    }

    @Test func flushReturnsUnterminatedTail() throws {
        var buffer = IntegrationsLineBuffer(maxLineBytes: 100)
        #expect(try buffer.append(Data("tail".utf8)).get().isEmpty)
        #expect(buffer.flush() == "tail")
    }

    @Test func overflowsOnLongLine() {
        var buffer = IntegrationsLineBuffer(maxLineBytes: 8)
        let result = buffer.append(Data("123456789".utf8))
        #expect(throws: IntegrationsLineBuffer.OverflowError.self) { try result.get() }
    }

    @Test func invalidUTF8IsReplacedNotCrashing() throws {
        var buffer = IntegrationsLineBuffer(maxLineBytes: 100)
        let lines = try buffer.append(Data([0x61, 0xFF, 0x62, 0x0A])).get()
        #expect(lines == ["a\u{FFFD}b"])
    }
}

struct IntegrationsDailyCountTests {
    @Test func resetsOnNextDay() {
        let calendar = integrationsUTCCalendar
        let morning = Date(timeIntervalSince1970: 1_700_000_000)
        let count = IntegrationsDailyCount.empty(at: morning, calendar: calendar)
            .incremented(at: morning, calendar: calendar)
            .incremented(at: morning.addingTimeInterval(60), calendar: calendar)
        #expect(count.count(at: morning, calendar: calendar) == 2)

        let tomorrow = morning.addingTimeInterval(86_400)
        #expect(count.count(at: tomorrow, calendar: calendar) == 0)
        #expect(count.incremented(at: tomorrow, calendar: calendar).count == 1)
    }
}
