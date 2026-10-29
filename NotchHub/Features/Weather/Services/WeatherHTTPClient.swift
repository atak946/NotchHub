import Foundation

/// Fetches raw response bodies; injectable so tests can serve fixtures.
protocol WeatherHTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

struct URLSessionWeatherFetcher: WeatherHTTPFetching {
    static let timeout: TimeInterval = 15
    private static let successCodes = 200..<300

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard Self.successCodes.contains(statusCode) else {
            throw WeatherError.badResponse(statusCode: statusCode)
        }
        return data
    }
}
