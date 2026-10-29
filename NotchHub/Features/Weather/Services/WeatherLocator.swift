import CoreLocation
import MapKit
import OSLog

/// Device location and reverse geocoding for the automatic weather location; injectable for tests.
@MainActor
protocol WeatherLocating: AnyObject {
    /// True once the user declined (or a policy blocks) location access.
    var isDenied: Bool { get }
    func currentCoordinate() async throws -> WeatherCoordinate
    func cityName(for coordinate: WeatherCoordinate) async -> String?
}

/// CoreLocation with when-in-use authorization and reduced accuracy; names come from MapKit reverse geocoding.
@MainActor
final class CoreLocationWeatherLocator: NSObject, WeatherLocating {
    static let timeout: Duration = .seconds(20)

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<WeatherCoordinate, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Weather")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func currentCoordinate() async throws -> WeatherCoordinate {
        guard continuation == nil else { throw WeatherError.locationBusy }
        guard !isDenied else { throw WeatherError.locationDenied }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            startTimeout()
            if manager.authorizationStatus == .notDetermined {
                // `locationManagerDidChangeAuthorization` requests the location once the user answers.
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    func cityName(for coordinate: WeatherCoordinate) async -> String? {
        let approximate = coordinate.approximated()
        let location = CLLocation(latitude: approximate.latitude, longitude: approximate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = .autoupdatingCurrent
        do {
            let items = try await request.mapItems
            return items.first?.addressRepresentations?.cityName
        } catch {
            logger.error("Reverse geocoding failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Private

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(WeatherError.locationUnavailable))
        }
    }

    fileprivate func finish(_ result: Result<WeatherCoordinate, any Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    fileprivate func authorizationChanged() {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            return
        case .denied, .restricted:
            finish(.failure(WeatherError.locationDenied))
        default:
            manager.requestLocation()
        }
    }
}

extension CoreLocationWeatherLocator: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = WeatherCoordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor [weak self] in
            self?.finish(.success(coordinate))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.logger.error("Location request failed: \(message, privacy: .public)")
            self?.finish(.failure(WeatherError.locationUnavailable))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.authorizationChanged()
        }
    }
}
