import Foundation

/// Request URLs and response decoding for the Open-Meteo forecast and geocoding APIs (no API key).
enum OpenMeteoAPI {
    static let forecastEndpoint = "https://api.open-meteo.com/v1/forecast"
    static let geocodingEndpoint = "https://geocoding-api.open-meteo.com/v1/search"
    static let forecastDays = 2
    static let maxSearchResults = 8
    private static let dayLength: TimeInterval = 86_400
    private static let hourLength: TimeInterval = 3600

    // MARK: - URLs

    /// Forecast in °C with Unix timestamps; the coordinate is approximated before it leaves the Mac.
    static func forecastURL(for coordinate: WeatherCoordinate) -> URL? {
        let approximate = coordinate.approximated()
        var components = URLComponents(string: forecastEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(approximate.latitude)),
            URLQueryItem(name: "longitude", value: String(approximate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
        ]
        return components?.url
    }

    static func searchURL(query: String, languageCode: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: geocodingEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: String(maxSearchResults)),
            URLQueryItem(name: "language", value: languageCode),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }

    // MARK: - Decoding

    static func decodeForecast(_ data: Data, fetchedAt: Date, placeName: String?) throws -> WeatherSnapshot {
        let response: ForecastResponse
        do {
            response = try decoder.decode(ForecastResponse.self, from: data)
        } catch {
            throw WeatherError.decoding
        }
        let current = response.current
        let currentTime = Date(timeIntervalSince1970: current.time)
        let range = todayRange(response.daily, at: current.time)
        return WeatherSnapshot(
            fetchedAt: fetchedAt,
            coordinate: WeatherCoordinate(latitude: response.latitude, longitude: response.longitude),
            placeName: placeName,
            temperature: current.temperature2m,
            condition: WeatherCondition(wmoCode: current.weatherCode),
            isDay: current.isDay != 0,
            high: range?.high ?? current.temperature2m,
            low: range?.low ?? current.temperature2m,
            hourly: hours(response.hourly).filter { $0.time > currentTime.addingTimeInterval(-hourLength) }
        )
    }

    static func decodeCities(_ data: Data) throws -> [WeatherCity] {
        let response: SearchResponse
        do {
            response = try decoder.decode(SearchResponse.self, from: data)
        } catch {
            throw WeatherError.decoding
        }
        return (response.results ?? []).map { result in
            WeatherCity(
                name: result.name,
                region: result.admin1,
                country: result.country,
                coordinate: WeatherCoordinate(latitude: result.latitude, longitude: result.longitude)
            )
        }
    }

    // MARK: - Private

    private static let decoder = JSONDecoder()

    /// Today's max / min: the daily entry whose local day contains the current time, else the first one.
    private static func todayRange(_ daily: Daily, at time: TimeInterval) -> (high: Double, low: Double)? {
        let count = min(daily.time.count, daily.temperature2mMax.count, daily.temperature2mMin.count)
        guard count > 0 else { return nil }
        let index = (0..<count).first { daily.time[$0] <= time && time < daily.time[$0] + dayLength } ?? 0
        guard let high = daily.temperature2mMax[index], let low = daily.temperature2mMin[index] else { return nil }
        return (high, low)
    }

    private static func hours(_ hourly: Hourly) -> [WeatherHour] {
        let count = min(hourly.time.count, hourly.temperature2m.count, hourly.weatherCode.count, hourly.isDay.count)
        return (0..<count).compactMap { index in
            guard let temperature = hourly.temperature2m[index], let code = hourly.weatherCode[index] else {
                return nil
            }
            let isDay = hourly.isDay[index] ?? 1
            return WeatherHour(
                time: Date(timeIntervalSince1970: hourly.time[index]),
                temperature: temperature,
                condition: WeatherCondition(wmoCode: code),
                isDay: isDay != 0
            )
        }
    }

    private struct ForecastResponse: Decodable {
        var latitude: Double
        var longitude: Double
        var current: Current
        var hourly: Hourly
        var daily: Daily
    }

    private struct Current: Decodable {
        var time: TimeInterval
        var temperature2m: Double
        var weatherCode: Int
        var isDay: Int

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    private struct Hourly: Decodable {
        var time: [TimeInterval]
        var temperature2m: [Double?]
        var weatherCode: [Int?]
        var isDay: [Int?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    private struct Daily: Decodable {
        var time: [TimeInterval]
        var temperature2mMax: [Double?]
        var temperature2mMin: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }

    private struct SearchResponse: Decodable {
        var results: [SearchResult]?
    }

    private struct SearchResult: Decodable {
        var name: String
        var latitude: Double
        var longitude: Double
        var country: String?
        var admin1: String?
    }
}
