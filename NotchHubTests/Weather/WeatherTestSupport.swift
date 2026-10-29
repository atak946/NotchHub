import Foundation
@testable import NotchHub

enum WeatherFixtures {
    /// Local midnight of the forecast day (Unix seconds) in the fixture.
    static let dayStart: TimeInterval = 1_793_232_000
    static let currentTime: TimeInterval = dayStart + 22 * 3600

    /// Open-Meteo forecast response (`timeformat=unixtime`) trimmed to a few hours; one hour has gaps.
    static let forecastJSON = """
    {
      "latitude": 41.02, "longitude": 28.98, "generationtime_ms": 0.1, "utc_offset_seconds": 10800,
      "timezone": "Europe/Istanbul", "timezone_abbreviation": "GMT+3", "elevation": 39.0,
      "current_units": {"time": "unixtime", "interval": "seconds", "temperature_2m": "°C", "weather_code": "wmo code", "is_day": ""},
      "current": {"time": \(Int(currentTime)), "interval": 900, "temperature_2m": 14.6, "weather_code": 2, "is_day": 0},
      "hourly_units": {"time": "unixtime", "temperature_2m": "°C", "weather_code": "wmo code", "is_day": ""},
      "hourly": {
        "time": [\(hours(-2...4))],
        "temperature_2m": [16.0, 15.1, 14.6, 13.9, null, 12.8, 12.1],
        "weather_code": [1, 2, 2, 3, 61, 61, 95],
        "is_day": [1, 0, 0, 0, 0, 0, 0]
      },
      "daily_units": {"time": "unixtime", "temperature_2m_max": "°C", "temperature_2m_min": "°C"},
      "daily": {
        "time": [\(Int(dayStart)), \(Int(dayStart + 86_400))],
        "temperature_2m_max": [19.4, 17.2],
        "temperature_2m_min": [11.3, 9.8]
      }
    }
    """

    static let searchJSON = """
    {"results": [
      {"id": 745044, "name": "İstanbul", "latitude": 41.01384, "longitude": 28.94966, "country_code": "TR",
       "admin1": "İstanbul", "country": "Türkiye", "timezone": "Europe/Istanbul"},
      {"id": 323786, "name": "Ankara", "latitude": 39.91987, "longitude": 32.85427, "country": "Türkiye", "admin1": "Ankara"}
    ], "generationtime_ms": 0.5}
    """

    static func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    static func snapshot(fetchedAt: Date, placeName: String? = "İstanbul") -> WeatherSnapshot {
        WeatherSnapshot(
            fetchedAt: fetchedAt,
            coordinate: WeatherCoordinate(latitude: 41.02, longitude: 28.98),
            placeName: placeName,
            temperature: 14.6,
            condition: .partlyCloudy,
            isDay: false,
            high: 19.4,
            low: 11.3,
            hourly: []
        )
    }

    private static func hours(_ offsets: ClosedRange<Int>) -> String {
        offsets.map { String(Int(currentTime) + $0 * 3600) }.joined(separator: ", ")
    }
}

/// Serves fixed bodies and records requested URLs.
final class WeatherFakeFetcher: WeatherHTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var forecast: Result<Data, any Error> = .success(WeatherFixtures.data(WeatherFixtures.forecastJSON))
    private var search: Result<Data, any Error> = .success(WeatherFixtures.data(WeatherFixtures.searchJSON))
    private var urls: [URL] = []

    var requestedURLs: [URL] { lock.withLock { urls } }

    func failForecast(_ error: any Error) {
        lock.withLock { forecast = .failure(error) }
    }

    func data(from url: URL) async throws -> Data {
        let result = lock.withLock {
            urls.append(url)
            return url.host() == "geocoding-api.open-meteo.com" ? search : forecast
        }
        return try result.get()
    }
}

@MainActor
final class WeatherFakeLocator: WeatherLocating {
    var result: Result<WeatherCoordinate, WeatherError> = .success(WeatherCoordinate(latitude: 41.0123, longitude: 28.9765))
    var name: String? = "Fatih"
    var isDenied = false
    private(set) var requestCount = 0

    func currentCoordinate() async throws -> WeatherCoordinate {
        requestCount += 1
        return try result.get()
    }

    func cityName(for coordinate: WeatherCoordinate) async -> String? {
        name
    }
}

@MainActor
final class WeatherMemoryCache: WeatherCaching {
    var stored: WeatherSnapshot?

    func load() -> WeatherSnapshot? { stored }
    func save(_ snapshot: WeatherSnapshot) { stored = snapshot }
    func clear() { stored = nil }
}

/// Manually advanced clock; `sleep` blocks until cancelled so loops never spin in tests.
final class WeatherTestClock: WeatherClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: WeatherFixtures.currentTime)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

func makeWeatherTestDefaults() -> UserDefaults {
    let suiteName = "NotchHubTests.Weather.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Could not create test defaults")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
