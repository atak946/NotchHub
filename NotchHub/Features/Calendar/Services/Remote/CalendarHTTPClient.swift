import Foundation

/// Minimal HTTP abstraction so remote calendar sources can be tested without the network.
protocol CalendarHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum CalendarHTTPError: Error, Equatable {
    case notHTTPResponse
}

/// `URLSession`-backed client without a URL cache or cookies: conditional requests (ETag / If-Modified-Since)
/// are managed by the caller so a 304 is always surfaced instead of being answered from a local cache.
struct URLSessionCalendarHTTPClient: CalendarHTTPClient {
    private static let requestTimeout: TimeInterval = 30

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CalendarHTTPError.notHTTPResponse }
        return (data, http)
    }
}

/// `application/x-www-form-urlencoded` body encoding (RFC 6749 token requests).
enum CalendarFormEncoding {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ fields: [(String, String)]) -> Data {
        let body = fields
            .map { "\(escape($0.0))=\(escape($0.1))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
