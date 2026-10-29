import Foundation
import Observation
import OSLog

/// Wall-clock time and sleeping for the weather refresh loop, injectable for tests.
protocol WeatherClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemWeatherClock: WeatherClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await PowerAwareScheduler.sleep(for: duration)
    }
}

/// Current weather for the expanded notch header: Open-Meteo forecast for the device location or a chosen city,
/// refreshed every 30 minutes and cached across relaunches. Failures are logged and never shown.
@MainActor
@Observable
final class WeatherService {
    static let retryInterval: Duration = .seconds(5 * 60)
    /// Shortest wait between loop runs, so a nearly stale cache never causes a busy loop.
    static let minimumDelay: Duration = .seconds(60)
    static let hourlyCount = 8
    private static let fallbackLanguageCode = "en"

    private enum Keys {
        static let isEnabled = "Weather.isEnabled"
        static let locationMode = "Weather.locationMode"
        static let city = "Weather.city"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetcher: any WeatherHTTPFetching
    @ObservationIgnored private let locator: any WeatherLocating
    @ObservationIgnored private let cache: any WeatherCaching
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private let loop: PowerAwareLoop
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Weather")
    /// True between `start()` and `stop()` from the app lifecycle.
    @ObservationIgnored private var isRunning = false
    /// Bumped on every location change so an in-flight fetch for the old place is discarded.
    @ObservationIgnored private var locationGeneration = 0

    private(set) var snapshot: WeatherSnapshot?
    /// Automatic mode only: location access was declined.
    private(set) var isLocationDenied = false
    private(set) var searchResults: [WeatherCity] = []
    private(set) var isSearching = false
    private(set) var searchFailed = false

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            updateLoop()
        }
    }

    var locationMode: WeatherLocationMode {
        didSet {
            guard locationMode != oldValue else { return }
            defaults.set(locationMode.rawValue, forKey: Keys.locationMode)
            locationDidChange()
        }
    }

    /// The manual city used in `.city` mode.
    var city: WeatherCity? {
        didSet {
            guard city != oldValue else { return }
            persistCity()
            if locationMode == .city { locationDidChange() }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        fetcher: any WeatherHTTPFetching = URLSessionWeatherFetcher(),
        locator: (any WeatherLocating)? = nil,
        cache: (any WeatherCaching)? = nil,
        clock: any WeatherClock = SystemWeatherClock(),
        power: (any PowerConditionsProviding)? = nil
    ) {
        self.defaults = defaults
        self.fetcher = fetcher
        self.locator = locator ?? CoreLocationWeatherLocator()
        self.cache = cache ?? UserDefaultsWeatherCache(defaults: defaults)
        self.clock = clock
        loop = PowerAwareLoop(priority: .standard, power: power, sleep: { try await clock.sleep(for: $0) })
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        locationMode = defaults.string(forKey: Keys.locationMode).flatMap(WeatherLocationMode.init) ?? .automatic
        city = defaults.data(forKey: Keys.city).flatMap { try? JSONDecoder().decode(WeatherCity.self, from: $0) }
        snapshot = self.cache.load()
    }

    // MARK: - Derived state

    /// The forecast if it is recent enough to show.
    func displaySnapshot(at now: Date) -> WeatherSnapshot? {
        guard isEnabled, WeatherCachePolicy.isDisplayable(snapshot, now: now) else { return nil }
        return snapshot
    }

    // MARK: - Lifecycle

    func start() {
        isRunning = true
        updateLoop()
    }

    func stop() {
        isRunning = false
        updateLoop()
    }

    /// One loop run: refreshes when the cache is stale and returns the delay until the next run. Internal for tests.
    func tick() async -> Duration {
        let now = clock.now
        guard WeatherCachePolicy.isStale(snapshot, now: now) else {
            let remaining = Duration.seconds(WeatherCachePolicy.timeUntilStale(snapshot, now: now))
            return max(remaining, Self.minimumDelay)
        }
        do {
            try await refresh()
            return .seconds(WeatherCachePolicy.refreshInterval)
        } catch {
            logger.error("Weather refresh failed: \(String(describing: error), privacy: .public)")
            return Self.retryInterval
        }
    }

    /// Fetches the forecast for the current location setting now. Internal for tests.
    func refresh() async throws {
        let generation = locationGeneration
        let (coordinate, placeName) = try await resolveLocation()
        guard let url = OpenMeteoAPI.forecastURL(for: coordinate) else { throw WeatherError.invalidURL }
        let data = try await fetcher.data(from: url)
        let fresh = try OpenMeteoAPI.decodeForecast(data, fetchedAt: clock.now, placeName: placeName)
        guard generation == locationGeneration else { return }
        snapshot = fresh
        cache.save(fresh)
    }

    // MARK: - City search

    func search(_ query: String) async {
        let languageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? Self.fallbackLanguageCode
        guard let url = OpenMeteoAPI.searchURL(query: query, languageCode: languageCode) else {
            searchResults = []
            searchFailed = false
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try OpenMeteoAPI.decodeCities(try await fetcher.data(from: url))
            searchResults = results
            searchFailed = false
        } catch {
            logger.error("City search failed: \(String(describing: error), privacy: .public)")
            searchResults = []
            searchFailed = true
        }
    }

    func clearSearch() {
        searchResults = []
        searchFailed = false
    }

    // MARK: - Private

    private func updateLoop() {
        let shouldRun = isRunning && isEnabled
        if shouldRun, !loop.isActive {
            loop.start { [weak self] in
                await self?.tick()
            }
        } else if !shouldRun, loop.isActive {
            loop.stop()
        }
    }

    private func resolveLocation() async throws -> (WeatherCoordinate, String?) {
        switch locationMode {
        case .city:
            guard let city else { throw WeatherError.noCitySelected }
            return (city.coordinate, city.name)
        case .automatic:
            do {
                let coordinate = try await locator.currentCoordinate()
                isLocationDenied = false
                return (coordinate, await locator.cityName(for: coordinate))
            } catch {
                isLocationDenied = locator.isDenied
                throw error
            }
        }
    }

    private func locationDidChange() {
        locationGeneration += 1
        snapshot = nil
        cache.clear()
        isLocationDenied = false
        loop.kick()
    }

    private func persistCity() {
        guard let city else {
            defaults.removeObject(forKey: Keys.city)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(city), forKey: Keys.city)
        } catch {
            logger.error("Saving the weather city failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
