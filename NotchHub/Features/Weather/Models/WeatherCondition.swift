import Foundation

/// Weather condition groups of the WMO 4677 codes that Open-Meteo reports as `weather_code`.
enum WeatherCondition: String, Codable, CaseIterable, Sendable {
    case clear
    case mainlyClear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case freezingDrizzle
    case rain
    case heavyRain
    case freezingRain
    case snow
    case snowGrains
    case rainShowers
    case snowShowers
    case thunderstorm
    case thunderstormHail
    case unknown

    private static let codeTable: [Int: WeatherCondition] = [
        0: .clear,
        1: .mainlyClear,
        2: .partlyCloudy,
        3: .overcast,
        45: .fog, 48: .fog,
        51: .drizzle, 53: .drizzle, 55: .drizzle,
        56: .freezingDrizzle, 57: .freezingDrizzle,
        61: .rain, 63: .rain,
        65: .heavyRain,
        66: .freezingRain, 67: .freezingRain,
        71: .snow, 73: .snow, 75: .snow,
        77: .snowGrains,
        80: .rainShowers, 81: .rainShowers, 82: .rainShowers,
        85: .snowShowers, 86: .snowShowers,
        95: .thunderstorm,
        96: .thunderstormHail, 99: .thunderstormHail,
    ]

    init(wmoCode: Int) {
        self = Self.codeTable[wmoCode] ?? .unknown
    }

    /// SF Symbol for the condition; clear and partly cloudy skies have night variants.
    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mainlyClear: isDay ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .freezingDrizzle, .freezingRain: "cloud.sleet.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .snow, .snowShowers: "cloud.snow.fill"
        case .snowGrains: "snowflake"
        case .rainShowers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .thunderstormHail: "cloud.hail.fill"
        case .unknown: "thermometer.medium"
        }
    }

    /// Localized condition name; clear skies read differently by day and by night.
    func title(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? String(localized: "Güneşli") : String(localized: "Açık hava")
        case .mainlyClear: isDay ? String(localized: "Çoğunlukla güneşli") : String(localized: "Çoğunlukla açık")
        case .partlyCloudy: String(localized: "Parçalı bulutlu")
        case .overcast: String(localized: "Çok bulutlu")
        case .fog: String(localized: "Sisli")
        case .drizzle: String(localized: "Çisenti")
        case .freezingDrizzle: String(localized: "Donan çisenti")
        case .rain: String(localized: "Yağmurlu")
        case .heavyRain: String(localized: "Şiddetli yağmur")
        case .freezingRain: String(localized: "Donan yağmur")
        case .snow: String(localized: "Karlı")
        case .snowGrains: String(localized: "Kar taneleri")
        case .rainShowers: String(localized: "Sağanak yağış")
        case .snowShowers: String(localized: "Kar sağanağı")
        case .thunderstorm: String(localized: "Gök gürültülü fırtına")
        case .thunderstormHail: String(localized: "Dolu ve fırtına")
        case .unknown: String(localized: "Bilinmiyor")
        }
    }
}
