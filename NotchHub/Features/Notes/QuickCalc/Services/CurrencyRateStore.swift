import Foundation
import Observation
import OSLog

/// Downloads the latest rates; faked in tests.
protocol CurrencyRatesFetching: Sendable {
    func fetchLatest(fetchedAt: Date) async throws -> CurrencyRates
}

/// Persists the last download between launches.
@MainActor
protocol CurrencyRatesCaching: AnyObject {
    func load() -> CurrencyRates?
    func save(_ rates: CurrencyRates)
}

/// Holds the current rates: served from cache while younger than `maxAge`, refreshed on demand otherwise.
/// A failed refresh keeps the older rates so conversions keep working offline.
@MainActor
@Observable
final class CurrencyRateStore {
    static let defaultMaxAge: TimeInterval = 12 * 60 * 60
    /// After a failed download, wait this long before trying again (typing must not hammer the API offline).
    static let defaultRetryDelay: TimeInterval = 60

    enum Status: Equatable, Sendable {
        case idle
        case loading
        case failed
    }

    private(set) var rates: CurrencyRates?
    private(set) var status: Status = .idle

    @ObservationIgnored private let fetcher: any CurrencyRatesFetching
    @ObservationIgnored private let cache: any CurrencyRatesCaching
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let maxAge: TimeInterval
    @ObservationIgnored private let retryDelay: TimeInterval
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastFailureAt: Date?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "QuickCalc")

    init(
        fetcher: any CurrencyRatesFetching,
        cache: any CurrencyRatesCaching,
        now: @escaping @Sendable () -> Date = Date.init,
        maxAge: TimeInterval = CurrencyRateStore.defaultMaxAge,
        retryDelay: TimeInterval = CurrencyRateStore.defaultRetryDelay
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.now = now
        self.maxAge = maxAge
        self.retryDelay = retryDelay
        rates = cache.load()
    }

    var isFresh: Bool {
        rates?.isFresh(at: now(), maxAge: maxAge) ?? false
    }

    /// Fetches when the rates are missing or older than `maxAge`; concurrent callers share one request.
    func refreshIfNeeded() async {
        guard !isFresh, !isBackingOff else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private var isBackingOff: Bool {
        guard let lastFailureAt else { return false }
        return now().timeIntervalSince(lastFailureAt) < retryDelay
    }

    private func performRefresh() async {
        status = .loading
        do {
            let latest = try await fetcher.fetchLatest(fetchedAt: now())
            rates = latest
            cache.save(latest)
            status = .idle
            lastFailureAt = nil
        } catch {
            lastFailureAt = now()
            logger.error("Currency rate refresh failed: \(error.localizedDescription, privacy: .public)")
            status = .failed
        }
    }
}

/// open.er-api.com (free, no key), quoted against USD.
struct OpenERAPIRatesFetcher: CurrencyRatesFetching {
    enum FetchError: Error {
        case badStatus(Int)
        case notHTTPResponse
    }

    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")
    private static let timeout: TimeInterval = 15

    func fetchLatest(fetchedAt: Date) async throws -> CurrencyRates {
        guard let url = Self.endpoint else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTPResponse }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.badStatus(http.statusCode) }
        return try OpenERAPIDecoder.decode(data, fetchedAt: fetchedAt)
    }
}

/// JSON blob in `UserDefaults`.
@MainActor
final class UserDefaultsCurrencyRatesCache: CurrencyRatesCaching {
    private static let key = "quickCalcCurrencyRates"
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "QuickCalc")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CurrencyRates? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        do {
            return try JSONDecoder().decode(CurrencyRates.self, from: data)
        } catch {
            logger.error("Discarding unreadable cached rates: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ rates: CurrencyRates) {
        do {
            defaults.set(try JSONEncoder().encode(rates), forKey: Self.key)
        } catch {
            logger.error("Could not cache rates: \(error.localizedDescription, privacy: .public)")
        }
    }
}
