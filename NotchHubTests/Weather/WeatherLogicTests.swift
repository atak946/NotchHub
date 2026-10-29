import Foundation
import Testing
@testable import NotchHub

struct WeatherConditionTests {
    @Test(arguments: [
        (0, WeatherCondition.clear), (1, .mainlyClear), (2, .partlyCloudy), (3, .overcast),
        (45, .fog), (48, .fog), (51, .drizzle), (55, .drizzle), (56, .freezingDrizzle),
        (61, .rain), (63, .rain), (65, .heavyRain), (67, .freezingRain), (71, .snow), (75, .snow),
        (77, .snowGrains), (80, .rainShowers), (82, .rainShowers), (85, .snowShowers), (86, .snowShowers),
        (95, .thunderstorm), (96, .thunderstormHail), (99, .thunderstormHail),
    ])
    func mapsWMOCodes(code: Int, expected: WeatherCondition) {
        #expect(WeatherCondition(wmoCode: code) == expected)
    }

    @Test(arguments: [-1, 4, 50, 100, 1000])
    func unknownCodesFallBack(code: Int) {
        #expect(WeatherCondition(wmoCode: code) == .unknown)
    }

    @Test func clearSkiesHaveNightVariants() {
        #expect(WeatherCondition.clear.symbolName(isDay: true) == "sun.max.fill")
        #expect(WeatherCondition.clear.symbolName(isDay: false) == "moon.stars.fill")
        #expect(WeatherCondition.partlyCloudy.symbolName(isDay: false) == "cloud.moon.fill")
        #expect(WeatherCondition.rain.symbolName(isDay: true) == WeatherCondition.rain.symbolName(isDay: false))
        #expect(WeatherCondition.clear.title(isDay: true) == "Güneşli")
        #expect(WeatherCondition.clear.title(isDay: false) == "Açık hava")
    }

    @Test func everyConditionHasASymbolAndTitle() {
        for condition in WeatherCondition.allCases {
            #expect(!condition.symbolName(isDay: true).isEmpty)
            #expect(!condition.title(isDay: false).isEmpty)
        }
    }
}

struct OpenMeteoDecodingTests {
    private let fetchedAt = Date(timeIntervalSince1970: WeatherFixtures.currentTime + 60)

    @Test func decodesForecastFixture() throws {
        let snapshot = try OpenMeteoAPI.decodeForecast(
            WeatherFixtures.data(WeatherFixtures.forecastJSON), fetchedAt: fetchedAt, placeName: "İstanbul"
        )
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.placeName == "İstanbul")
        #expect(snapshot.coordinate == WeatherCoordinate(latitude: 41.02, longitude: 28.98))
        #expect(snapshot.temperature == 14.6)
        #expect(snapshot.condition == .partlyCloudy)
        #expect(!snapshot.isDay)
        #expect(snapshot.high == 19.4)
        #expect(snapshot.low == 11.3)
    }

    @Test func keepsUpcomingHoursAndSkipsGaps() throws {
        let snapshot = try OpenMeteoAPI.decodeForecast(
            WeatherFixtures.data(WeatherFixtures.forecastJSON), fetchedAt: fetchedAt, placeName: nil
        )
        let start = WeatherFixtures.currentTime
        #expect(snapshot.hourly.map(\.time.timeIntervalSince1970) == [start, start + 3600, start + 3 * 3600, start + 4 * 3600])
        #expect(snapshot.hourly.map(\.condition) == [.partlyCloudy, .overcast, .rain, .thunderstorm])
        #expect(snapshot.hourly.allSatisfy { !$0.isDay })
        let now = Date(timeIntervalSince1970: start + 1800)
        #expect(snapshot.upcomingHours(from: now, limit: 2).count == 2)
        #expect(snapshot.upcomingHours(from: now, limit: 8).first?.time.timeIntervalSince1970 == start)
    }

    @Test func rejectsMalformedForecast() {
        #expect(throws: WeatherError.decoding) {
            try OpenMeteoAPI.decodeForecast(WeatherFixtures.data("{\"error\":true}"), fetchedAt: fetchedAt, placeName: nil)
        }
    }

    @Test func decodesCitySearch() throws {
        let cities = try OpenMeteoAPI.decodeCities(WeatherFixtures.data(WeatherFixtures.searchJSON))
        #expect(cities.map(\.name) == ["İstanbul", "Ankara"])
        #expect(cities[0].displayName == "İstanbul, Türkiye")
        #expect(cities[0].coordinate.latitude == 41.01384)
        #expect(try OpenMeteoAPI.decodeCities(WeatherFixtures.data("{\"generationtime_ms\":0.2}")).isEmpty)
    }

    @Test func forecastURLUsesApproximateCoordinates() throws {
        let url = try #require(OpenMeteoAPI.forecastURL(for: WeatherCoordinate(latitude: 41.012345, longitude: 28.976543)))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "api.open-meteo.com")
        #expect(query["latitude"] == "41.01")
        #expect(query["longitude"] == "28.98")
        #expect(query["timezone"] == "auto")
        #expect(query["timeformat"] == "unixtime")
        #expect(query["current"]?.contains("weather_code") == true)
    }

    @Test func searchURLRequiresAQuery() throws {
        #expect(OpenMeteoAPI.searchURL(query: "   ", languageCode: "tr") == nil)
        let url = try #require(OpenMeteoAPI.searchURL(query: " İzmir ", languageCode: "tr"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "name", value: "İzmir")))
        #expect(items.contains(URLQueryItem(name: "language", value: "tr")))
    }
}

struct WeatherCachePolicyTests {
    private let fetchedAt = Date(timeIntervalSince1970: WeatherFixtures.currentTime)

    @Test func freshUntilTheRefreshInterval() {
        let snapshot = WeatherFixtures.snapshot(fetchedAt: fetchedAt)
        #expect(WeatherCachePolicy.isStale(nil, now: fetchedAt))
        #expect(!WeatherCachePolicy.isStale(snapshot, now: fetchedAt.addingTimeInterval(29 * 60)))
        #expect(WeatherCachePolicy.isStale(snapshot, now: fetchedAt.addingTimeInterval(30 * 60)))
        #expect(WeatherCachePolicy.timeUntilStale(snapshot, now: fetchedAt.addingTimeInterval(10 * 60)) == 20 * 60)
        #expect(WeatherCachePolicy.timeUntilStale(snapshot, now: fetchedAt.addingTimeInterval(40 * 60)) == 0)
    }

    @Test func futureFetchTimesCountAsStale() {
        let snapshot = WeatherFixtures.snapshot(fetchedAt: fetchedAt.addingTimeInterval(3600))
        #expect(WeatherCachePolicy.isStale(snapshot, now: fetchedAt))
        #expect(!WeatherCachePolicy.isDisplayable(snapshot, now: fetchedAt))
    }

    @Test func oldForecastsAreHidden() {
        let snapshot = WeatherFixtures.snapshot(fetchedAt: fetchedAt)
        #expect(WeatherCachePolicy.isDisplayable(snapshot, now: fetchedAt.addingTimeInterval(2 * 3600)))
        #expect(!WeatherCachePolicy.isDisplayable(snapshot, now: fetchedAt.addingTimeInterval(3 * 3600)))
        #expect(!WeatherCachePolicy.isDisplayable(nil, now: fetchedAt))
    }
}

struct WeatherTemperatureFormatterTests {
    private let turkish = Locale(identifier: "tr_TR")
    private let american = Locale(identifier: "en_US")
    private let british = Locale(identifier: "en_GB")

    @Test func choosesUnitByMeasurementSystem() {
        #expect(WeatherTemperatureFormatter.unit(for: turkish) == .celsius)
        #expect(WeatherTemperatureFormatter.unit(for: british) == .celsius)
        #expect(WeatherTemperatureFormatter.unit(for: american) == .fahrenheit)
    }

    @Test func convertsAndRounds() {
        #expect(WeatherTemperatureFormatter.roundedValue(celsius: 21.6, locale: turkish) == 22)
        #expect(WeatherTemperatureFormatter.roundedValue(celsius: 22, locale: american) == 72)
        #expect(WeatherTemperatureFormatter.roundedValue(celsius: -0.4, locale: turkish) == 0)
        #expect(WeatherTemperatureFormatter.roundedValue(celsius: -0.4, locale: turkish).sign == .plus)
    }

    @Test func formatsCompactAndFull() {
        #expect(WeatherTemperatureFormatter.compact(celsius: 21.6, locale: turkish) == "22°")
        #expect(WeatherTemperatureFormatter.compact(celsius: -0.4, locale: turkish) == "0°")
        #expect(WeatherTemperatureFormatter.compact(celsius: 22, locale: american) == "72°")
        #expect(WeatherTemperatureFormatter.full(celsius: 21.6, locale: turkish).contains("°C"))
        #expect(WeatherTemperatureFormatter.full(celsius: 22, locale: american).hasPrefix("72°"))
    }
}
