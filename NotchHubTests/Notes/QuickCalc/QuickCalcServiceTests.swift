import Foundation
import Testing
@testable import NotchHub

/// Fetcher that returns queued results and counts calls.
final class FakeRatesFetcher: CurrencyRatesFetching, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var queued: [Result<[String: Double], Failure>]
    private(set) var callCount = 0

    init(_ queued: [Result<[String: Double], Failure>]) {
        self.queued = queued
    }

    func fetchLatest(fetchedAt: Date) async throws -> CurrencyRates {
        let next: Result<[String: Double], Failure> = lock.withLock {
            callCount += 1
            return queued.isEmpty ? .failure(Failure()) : queued.removeFirst()
        }
        let rates = try next.get()
        return CurrencyRates(base: "USD", rates: rates, updatedAt: fetchedAt, fetchedAt: fetchedAt)
    }
}

@MainActor
final class InMemoryRatesCache: CurrencyRatesCaching {
    var stored: CurrencyRates?
    private(set) var saveCount = 0

    init(_ stored: CurrencyRates? = nil) {
        self.stored = stored
    }

    func load() -> CurrencyRates? { stored }

    func save(_ rates: CurrencyRates) {
        stored = rates
        saveCount += 1
    }
}

/// Mutable clock for cache-age tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_761_696_000)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

func makeQuickCalcDefaults() -> UserDefaults {
    let (suiteName, defaults) = TestDefaults.makeSuite("QuickCalc.\(UUID().uuidString)")
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
struct QuickCalcServiceTests {
    private let turkish = Locale(identifier: "tr_TR")

    private func makeService(
        defaults: UserDefaults = makeQuickCalcDefaults(),
        fetcher: FakeRatesFetcher = FakeRatesFetcher([]),
        copied: @escaping @MainActor (String) -> Void = { _ in }
    ) -> QuickCalcService {
        let clock = TestClock()
        let store = CurrencyRateStore(fetcher: fetcher, cache: InMemoryRatesCache(), now: { clock.now })
        return QuickCalcService(defaults: defaults, rateStore: store, locale: turkish, copy: copied)
    }

    @Test func enabledByDefaultAndPersisted() {
        let defaults = makeQuickCalcDefaults()
        let service = makeService(defaults: defaults)
        #expect(service.isEnabled)
        service.isEnabled = false
        #expect(!makeService(defaults: defaults).isEnabled)
    }

    @Test func disablingLeavesCalculatorMode() {
        let service = makeService()
        service.setActive(true)
        #expect(service.isActive)
        #expect(service.wantsFocus)
        service.isEnabled = false
        #expect(!service.isActive)
        service.setActive(true)
        #expect(!service.isActive)
    }

    @Test func evaluatesLiveAsInputChanges() {
        let service = makeService()
        service.input = "12,5*3"
        #expect(service.outcome == .value(.number(37.5)))
        #expect(service.displayText == "37,5")
        service.input = "12,5*"
        #expect(service.outcome == .failure(.unexpectedEnd))
        #expect(service.displayText == nil)
    }

    @Test func commitCopiesUngroupedResultAndRecordsHistory() {
        var copied: [String] = []
        let service = makeService { copied.append($0) }
        service.input = "1234,5*2"

        #expect(service.commit())
        #expect(copied == ["2469"])
        #expect(service.history.map(\.expression) == ["1234,5*2"])
        #expect(service.history.first?.result == "2.469")
    }

    @Test func commitWithoutResultDoesNothing() {
        var copied: [String] = []
        let service = makeService { copied.append($0) }
        service.input = "1+"
        #expect(!service.commit())
        #expect(copied.isEmpty)
        #expect(service.history.isEmpty)
    }

    @Test func historyKeepsLastFiveNewestFirstAndSkipsRepeats() {
        let defaults = makeQuickCalcDefaults()
        let service = makeService(defaults: defaults)
        for index in 1...7 {
            service.input = "\(index)+0"
            service.commit()
            service.commit()
        }
        #expect(service.history.map(\.expression) == ["7+0", "6+0", "5+0", "4+0", "3+0"])
        #expect(makeService(defaults: defaults).history.map(\.expression) == ["7+0", "6+0", "5+0", "4+0", "3+0"])

        service.clearHistory()
        #expect(makeService(defaults: defaults).history.isEmpty)
    }

    @Test func reuseRestoresExpressionAndRequestsFocus() {
        let service = makeService()
        service.input = "2^10"
        service.commit()
        service.input = ""
        service.wantsFocus = false

        service.reuse(service.history[0])
        #expect(service.input == "2^10")
        #expect(service.outcome == .value(.number(1024)))
        #expect(service.wantsFocus)
    }

    @Test func currencyInputFetchesRatesThenEvaluates() async {
        let fetcher = FakeRatesFetcher([.success(["USD": 1, "TRY": 40])])
        let service = makeService(fetcher: fetcher)
        service.input = "100 usd tl"
        #expect(service.outcome == .needsRates)

        await service.refreshRatesIfNeeded()

        #expect(fetcher.callCount == 1)
        #expect(service.value?.amount == 4000)
        #expect(service.displayText == "4.000,00 TRY")

        await service.refreshRatesIfNeeded()
        #expect(fetcher.callCount == 1)
    }

    @Test func nonCurrencyInputNeverFetches() async {
        let fetcher = FakeRatesFetcher([.success(["USD": 1])])
        let service = makeService(fetcher: fetcher)
        service.input = "5 km mil"
        await service.refreshRatesIfNeeded()
        #expect(fetcher.callCount == 0)
    }
}
