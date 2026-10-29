import Foundation

/// A user-configured health-check target.
struct MonitoredEndpoint: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Method: String, Codable, CaseIterable, Identifiable, Sendable {
        case get = "GET"
        case head = "HEAD"

        var id: String { rawValue }
    }

    static let intervalRange = 30...600
    static let statusCodeRange = 100...599
    static let defaultInterval = 60
    static let intervalOptions = [30, 60, 120, 300, 600]

    var id: UUID
    var name: String
    var url: String
    var method: Method
    /// Seconds between checks, within `intervalRange`.
    var intervalSeconds: Int
    var expectedStatusLower: Int
    var expectedStatusUpper: Int
    var requiresVPN: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        url: String = "https://",
        method: Method = .get,
        intervalSeconds: Int = MonitoredEndpoint.defaultInterval,
        expectedStatusLower: Int = 200,
        expectedStatusUpper: Int = 399,
        requiresVPN: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.method = method
        self.intervalSeconds = intervalSeconds
        self.expectedStatusLower = expectedStatusLower
        self.expectedStatusUpper = expectedStatusUpper
        self.requiresVPN = requiresVPN
    }

    var expectedStatus: ClosedRange<Int> {
        min(expectedStatusLower, expectedStatusUpper)...max(expectedStatusLower, expectedStatusUpper)
    }

    var resolvedURL: URL? {
        URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (resolvedURL?.host() ?? url) : trimmed
    }

    var isHTTPS: Bool { resolvedURL?.scheme?.lowercased() == "https" }
}

enum EndpointValidationError: Error, Equatable, Sendable {
    case emptyName
    case invalidURL
    case unsupportedScheme
    case missingHost
    case intervalOutOfRange
    case invalidStatusRange

    var message: String {
        switch self {
        case .emptyName: String(localized: "Bir ad gir.")
        case .invalidURL: String(localized: "Geçerli bir URL gir.")
        case .unsupportedScheme: String(localized: "Yalnızca http:// ve https:// URL'leri desteklenir.")
        case .missingHost: String(localized: "URL'de bir ana makine adı olmalı.")
        case .intervalOutOfRange: String(localized: "Aralık 30 saniye ile 10 dakika arasında olmalı.")
        case .invalidStatusRange: String(localized: "Beklenen durum 100–599 aralığında olmalı.")
        }
    }
}

enum EndpointValidator {
    static let allowedSchemes: Set<String> = ["http", "https"]
    static let maxNameLength = 60

    static func validate(_ endpoint: MonitoredEndpoint) -> [EndpointValidationError] {
        var errors: [EndpointValidationError] = []
        let name = endpoint.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > maxNameLength {
            errors.append(.emptyName)
        }
        if let error = validateURL(endpoint.url) {
            errors.append(error)
        }
        if !MonitoredEndpoint.intervalRange.contains(endpoint.intervalSeconds) {
            errors.append(.intervalOutOfRange)
        }
        let codes = MonitoredEndpoint.statusCodeRange
        if !codes.contains(endpoint.expectedStatusLower)
            || !codes.contains(endpoint.expectedStatusUpper)
            || endpoint.expectedStatusLower > endpoint.expectedStatusUpper {
            errors.append(.invalidStatusRange)
        }
        return errors
    }

    static func isValid(_ endpoint: MonitoredEndpoint) -> Bool {
        validate(endpoint).isEmpty
    }

    private static func validateURL(_ text: String) -> EndpointValidationError? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased()
        else {
            return .invalidURL
        }
        guard allowedSchemes.contains(scheme) else { return .unsupportedScheme }
        guard let host = components.host, !host.isEmpty else { return .missingHost }
        return nil
    }
}

/// JSON persistence of the endpoint list in UserDefaults.
struct EndpointStore {
    static let endpointsKey = "Endpoints.list"

    let defaults: UserDefaults

    func load() -> [MonitoredEndpoint] {
        guard let data = defaults.data(forKey: Self.endpointsKey) else { return [] }
        return (try? JSONDecoder().decode([MonitoredEndpoint].self, from: data)) ?? []
    }

    func save(_ endpoints: [MonitoredEndpoint]) throws {
        let data = try JSONEncoder().encode(endpoints)
        defaults.set(data, forKey: Self.endpointsKey)
    }
}
