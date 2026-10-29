import Foundation

/// A latitude / longitude pair. Coordinates sent to remote services are always `approximated()`.
struct WeatherCoordinate: Codable, Equatable, Hashable, Sendable {
    /// Two decimals is roughly one kilometre: enough for a forecast, too coarse to pinpoint an address.
    static let approximationScale = 100.0

    var latitude: Double
    var longitude: Double

    func approximated() -> WeatherCoordinate {
        WeatherCoordinate(
            latitude: (latitude * Self.approximationScale).rounded() / Self.approximationScale,
            longitude: (longitude * Self.approximationScale).rounded() / Self.approximationScale
        )
    }
}

/// A city picked from the geocoding search, used instead of the device location.
struct WeatherCity: Codable, Equatable, Hashable, Identifiable, Sendable {
    var name: String
    var region: String?
    var country: String?
    var coordinate: WeatherCoordinate

    var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }

    /// "Name, Region, Country" without empty or repeated parts.
    var displayName: String {
        var parts = [name]
        for part in [region, country].compactMap({ $0 }) where !part.isEmpty && !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: ", ")
    }
}

/// One hourly forecast entry.
struct WeatherHour: Codable, Equatable, Identifiable, Sendable {
    var time: Date
    /// Degrees Celsius.
    var temperature: Double
    var condition: WeatherCondition
    var isDay: Bool

    var id: Date { time }
}

/// A complete forecast as fetched and cached. Temperatures are in degrees Celsius.
struct WeatherSnapshot: Codable, Equatable, Sendable {
    var fetchedAt: Date
    var coordinate: WeatherCoordinate
    var placeName: String?
    var temperature: Double
    var condition: WeatherCondition
    var isDay: Bool
    var high: Double
    var low: Double
    var hourly: [WeatherHour]

    /// Up to `limit` hourly entries starting with the hour that contains `now`.
    func upcomingHours(from now: Date, limit: Int) -> [WeatherHour] {
        let hourStart = now.addingTimeInterval(-WeatherSnapshot.hourLength)
        return Array(hourly.filter { $0.time > hourStart }.prefix(max(0, limit)))
    }

    private static let hourLength: TimeInterval = 3600
}

/// How the forecast location is chosen.
enum WeatherLocationMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case city

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "Otomatik")
        case .city: String(localized: "Şehir")
        }
    }
}

enum WeatherError: Error, Equatable {
    case locationDenied
    case locationUnavailable
    case locationBusy
    case noCitySelected
    case badResponse(statusCode: Int)
    case invalidURL
    case decoding
}
