import Foundation
import OSLog

/// Persists the last forecast so the notch shows weather right after a relaunch.
@MainActor
protocol WeatherCaching: AnyObject {
    func load() -> WeatherSnapshot?
    func save(_ snapshot: WeatherSnapshot)
    func clear()
}

/// JSON-encoded snapshot in UserDefaults.
@MainActor
final class UserDefaultsWeatherCache: WeatherCaching {
    static let key = "Weather.cachedSnapshot"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Weather")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        do {
            return try JSONDecoder().decode(WeatherSnapshot.self, from: data)
        } catch {
            logger.error("Discarding unreadable weather cache: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: Self.key)
            return nil
        }
    }

    func save(_ snapshot: WeatherSnapshot) {
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.key)
        } catch {
            logger.error("Weather cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
