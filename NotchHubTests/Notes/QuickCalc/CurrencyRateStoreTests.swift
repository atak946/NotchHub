import Foundation
import Testing
@testable import NotchHub

@MainActor
struct CurrencyRateStoreTests {
    private static let hour: TimeInterval = 60 * 60

    private func cached(at date: Date) -> CurrencyRates {
        CurrencyRates(base: "USD", rates: ["USD": 1, "TRY": 30], updatedAt: date, fetchedAt: date)
    }

    @Test func loadsCacheAndSkipsFetchWhileFresh() async {
        let clock = TestClock()
        let fetcher = FakeRatesFetcher([.success(["USD": 1, "TRY": 40])])
        let store = CurrencyRateStore(fetcher: fetcher, cache: InMemoryRatesCache(cached(at: clock.now)), now: { clock.now })

        clock.advance(by: 11 * Self.hour)
        await store.refreshIfNeeded()

        #expect(fetcher.callCount == 0)
        #expect(store.rates?.rates["TRY"] == 30)
        #expect(store.isFresh)
    }

    @Test func refetchesAfterTwelveHoursAndSavesToCache() async {
        let clock = TestClock()
        let cache = InMemoryRatesCache(cached(at: clock.now))
        let fetcher = FakeRatesFetcher([.success(["USD": 1, "TRY": 40])])
        let store = CurrencyRateStore(fetcher: fetcher, cache: cache, now: { clock.now })

        clock.advance(by: 12 * Self.hour)
        #expect(!store.isFresh)
        await store.refreshIfNeeded()

        #expect(fetcher.callCount == 1)
        #expect(store.rates?.rates["TRY"] == 40)
        #expect(cache.saveCount == 1)
        #expect(store.status == .idle)
    }

    @Test func failedRefreshKeepsStaleRatesAndBacksOff() async {
        let clock = TestClock()
        let fetcher = FakeRatesFetcher([.failure(.init()), .success(["USD": 1, "TRY": 41])])
        let store = CurrencyRateStore(fetcher: fetcher, cache: InMemoryRatesCache(cached(at: clock.now)), now: { clock.now })
        clock.advance(by: 13 * Self.hour)

        await store.refreshIfNeeded()
        #expect(store.status == .failed)
        #expect(store.rates?.rates["TRY"] == 30)

        await store.refreshIfNeeded()
        #expect(fetcher.callCount == 1)

        clock.advance(by: CurrencyRateStore.defaultRetryDelay)
        await store.refreshIfNeeded()
        #expect(fetcher.callCount == 2)
        #expect(store.rates?.rates["TRY"] == 41)
        #expect(store.status == .idle)
    }

    @Test func concurrentRefreshesShareOneRequest() async {
        let fetcher = FakeRatesFetcher([.success(["USD": 1]), .success(["USD": 1])])
        let store = CurrencyRateStore(fetcher: fetcher, cache: InMemoryRatesCache(), now: Date.init)

        async let first: Void = store.refreshIfNeeded()
        async let second: Void = store.refreshIfNeeded()
        _ = await (first, second)

        #expect(fetcher.callCount == 1)
    }

    @Test func userDefaultsCacheRoundTrips() {
        let defaults = makeQuickCalcDefaults()
        let rates = cached(at: Date(timeIntervalSince1970: 1_700_000_000))
        UserDefaultsCurrencyRatesCache(defaults: defaults).save(rates)
        #expect(UserDefaultsCurrencyRatesCache(defaults: defaults).load() == rates)
    }
}

struct CurrencyRatesTests {
    private static let fetchedAt = Date(timeIntervalSince1970: 1_761_700_000)

    @Test func decodesOpenERAPIPayload() throws {
        let json = """
        {"result":"success","provider":"https://www.exchangerate-api.com","time_last_update_unix":1761696151,
         "time_last_update_utc":"Wed, 29 Oct 2026 00:02:31 +0000","base_code":"USD",
         "rates":{"USD":1,"TRY":41.95,"EUR":0.858}}
        """
        let rates = try OpenERAPIDecoder.decode(Data(json.utf8), fetchedAt: Self.fetchedAt)

        #expect(rates.base == "USD")
        #expect(rates.rates["TRY"] == 41.95)
        #expect(rates.updatedAt == Date(timeIntervalSince1970: 1_761_696_151))
        #expect(rates.fetchedAt == Self.fetchedAt)
    }

    @Test func rejectsErrorAndMalformedPayloads() {
        let error = Data(#"{"result":"error","error-type":"unsupported-code"}"#.utf8)
        #expect(throws: OpenERAPIDecoder.DecodeError.providerError("unsupported-code")) {
            try OpenERAPIDecoder.decode(error, fetchedAt: Self.fetchedAt)
        }
        #expect(throws: OpenERAPIDecoder.DecodeError.malformed) {
            try OpenERAPIDecoder.decode(Data("not json".utf8), fetchedAt: Self.fetchedAt)
        }
        let noRates = Data(#"{"result":"success","base_code":"USD","time_last_update_unix":1,"rates":{}}"#.utf8)
        #expect(throws: OpenERAPIDecoder.DecodeError.malformed) {
            try OpenERAPIDecoder.decode(noRates, fetchedAt: Self.fetchedAt)
        }
    }

    @Test func convertsThroughTheBaseAndRejectsBadRates() {
        let rates = CurrencyRates(
            base: "USD",
            rates: ["TRY": 40, "EUR": 0.5, "BAD": 0],
            updatedAt: Self.fetchedAt,
            fetchedAt: Self.fetchedAt
        )
        #expect(rates.convert(10, from: "EUR", to: "TRY") == 800)
        #expect(rates.convert(1, from: "USD", to: "USD") == 1)
        #expect(rates.convert(1, from: "BAD", to: "TRY") == nil)
        #expect(rates.convert(1, from: "USD", to: "XYZ") == nil)
    }

    @Test func freshnessWindow() {
        let rates = CurrencyRates(base: "USD", rates: ["USD": 1], updatedAt: Self.fetchedAt, fetchedAt: Self.fetchedAt)
        #expect(rates.isFresh(at: Self.fetchedAt.addingTimeInterval(100), maxAge: 200))
        #expect(!rates.isFresh(at: Self.fetchedAt.addingTimeInterval(200), maxAge: 200))
        #expect(!rates.isFresh(at: Self.fetchedAt.addingTimeInterval(-1), maxAge: 200))
    }
}

struct QuickCalcFormatterTests {
    private let turkish = QuickCalcFormatter(locale: Locale(identifier: "tr_TR"))
    private let english = QuickCalcFormatter(locale: Locale(identifier: "en_US"))

    @Test func numbersFollowTheLocale() {
        #expect(turkish.display(.number(1234.5)) == "1.234,5")
        #expect(english.display(.number(1234.5)) == "1,234.5")
        #expect(turkish.copyText(.number(1234.5)) == "1234,5")
        #expect(english.copyText(.number(0.1 + 0.2)) == "0.3")
    }

    @Test func currencyUsesTwoDecimalsAndCode() {
        let value = QuickCalcValue.currency(3412.5, code: "TRY", rateDate: .now)
        #expect(turkish.display(value) == "3.412,50 TRY")
        #expect(turkish.copyText(value) == "3412,50")
        #expect(english.display(.currency(0.02346, code: "USD", rateDate: .now)) == "0.0235 USD")
    }

    @Test func measurementsShowTheTargetUnit() {
        let text = english.display(.measurement(3.1068559611866697, unit: .mile))
        #expect(text.hasPrefix("3.106856"))
        #expect(text.contains("mi"))
    }

    @Test func extremeMagnitudesUseScientificNotation() {
        #expect(english.display(.number(1e20)).uppercased().contains("E"))
        #expect(english.display(.number(1e-9)).uppercased().contains("E"))
    }
}
