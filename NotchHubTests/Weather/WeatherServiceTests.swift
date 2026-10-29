import Foundation
import Testing
@testable import NotchHub

@MainActor
struct WeatherServiceTests {
    private let defaults = makeWeatherTestDefaults()
    private let fetcher = WeatherFakeFetcher()
    private let locator = WeatherFakeLocator()
    private let cache = WeatherMemoryCache()
    private let clock = WeatherTestClock()

    private func makeService() -> WeatherService {
        WeatherService(
            defaults: defaults, fetcher: fetcher, locator: locator, cache: cache, clock: clock,
            power: StaticPowerConditions()
        )
    }

    @Test func defaultsToEnabledAutomatic() {
        let service = makeService()
        #expect(service.isEnabled)
        #expect(service.locationMode == .automatic)
        #expect(service.city == nil)
        #expect(service.snapshot == nil)
    }

    @Test func refreshUsesDeviceLocationAndCaches() async throws {
        let service = makeService()
        try await service.refresh()
        #expect(service.snapshot?.placeName == "Fatih")
        #expect(service.snapshot?.temperature == 14.6)
        #expect(cache.stored == service.snapshot)
        let url = try #require(fetcher.requestedURLs.last)
        #expect(url.query()?.contains("latitude=41.01") == true)
    }

    @Test func tickSkipsFetchWhileCacheIsFresh() async {
        cache.stored = WeatherFixtures.snapshot(fetchedAt: clock.now.addingTimeInterval(-10 * 60))
        let service = makeService()
        let delay = await service.tick()
        #expect(fetcher.requestedURLs.isEmpty)
        #expect(delay == .seconds(20 * 60))
        #expect(service.displaySnapshot(at: clock.now) != nil)
    }

    @Test func tickRefreshesStaleCache() async {
        cache.stored = WeatherFixtures.snapshot(fetchedAt: clock.now.addingTimeInterval(-31 * 60))
        let service = makeService()
        let delay = await service.tick()
        #expect(fetcher.requestedURLs.count == 1)
        #expect(delay == .seconds(WeatherCachePolicy.refreshInterval))
        #expect(service.snapshot?.fetchedAt == clock.now)
    }

    @Test func failuresKeepTheCacheAndRetryLater() async {
        let old = WeatherFixtures.snapshot(fetchedAt: clock.now.addingTimeInterval(-40 * 60))
        cache.stored = old
        fetcher.failForecast(WeatherError.badResponse(statusCode: 503))
        let service = makeService()
        let delay = await service.tick()
        #expect(delay == WeatherService.retryInterval)
        #expect(service.snapshot == old)
    }

    @Test func deniedLocationIsReported() async {
        locator.result = .failure(.locationDenied)
        locator.isDenied = true
        let service = makeService()
        _ = await service.tick()
        #expect(service.isLocationDenied)
        #expect(fetcher.requestedURLs.isEmpty)
    }

    @Test func manualCityIsUsedAndPersisted() async throws {
        let service = makeService()
        let city = WeatherCity(
            name: "Ankara", region: "Ankara", country: "Türkiye",
            coordinate: WeatherCoordinate(latitude: 39.91987, longitude: 32.85427)
        )
        service.locationMode = .city
        service.city = city
        try await service.refresh()
        #expect(locator.requestCount == 0)
        #expect(service.snapshot?.placeName == "Ankara")
        #expect(fetcher.requestedURLs.last?.query()?.contains("latitude=39.92") == true)

        let reloaded = makeService()
        #expect(reloaded.locationMode == .city)
        #expect(reloaded.city == city)
    }

    @Test func cityModeWithoutCityFails() async {
        let service = makeService()
        service.locationMode = .city
        await #expect(throws: WeatherError.noCitySelected) {
            try await service.refresh()
        }
    }

    @Test func changingLocationClearsTheCache() {
        cache.stored = WeatherFixtures.snapshot(fetchedAt: clock.now)
        let service = makeService()
        #expect(service.snapshot != nil)
        service.locationMode = .city
        #expect(service.snapshot == nil)
        #expect(cache.stored == nil)
    }

    @Test func disabledServiceShowsNothing() {
        cache.stored = WeatherFixtures.snapshot(fetchedAt: clock.now)
        let service = makeService()
        service.isEnabled = false
        #expect(service.displaySnapshot(at: clock.now) == nil)
        #expect(makeService().isEnabled == false)
    }

    @Test func searchesCities() async {
        let service = makeService()
        await service.search("Ist")
        #expect(service.searchResults.map(\.name) == ["İstanbul", "Ankara"])
        #expect(!service.searchFailed)
        await service.search("  ")
        #expect(service.searchResults.isEmpty)
    }

    @Test func userDefaultsCacheSurvivesRelaunch() {
        let snapshot = WeatherFixtures.snapshot(fetchedAt: clock.now)
        UserDefaultsWeatherCache(defaults: defaults).save(snapshot)
        #expect(UserDefaultsWeatherCache(defaults: defaults).load() == snapshot)
        defaults.set(Data("garbage".utf8), forKey: UserDefaultsWeatherCache.key)
        #expect(UserDefaultsWeatherCache(defaults: defaults).load() == nil)
        #expect(defaults.data(forKey: UserDefaultsWeatherCache.key) == nil)
    }
}
