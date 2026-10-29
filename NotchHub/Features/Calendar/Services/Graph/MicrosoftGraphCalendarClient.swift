import Foundation

enum MicrosoftGraphError: Error, Equatable, LocalizedError {
    case unauthorized
    case http(Int)
    case invalidResponse
    case untrustedNextLink

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Microsoft 365 erişim belirtecini reddetti."
        case let .http(code): "Microsoft Graph hatası (HTTP \(code))."
        case .invalidResponse: "Microsoft Graph'ten beklenmeyen yanıt."
        case .untrustedNextLink: "Microsoft Graph beklenmeyen bir sayfalama bağlantısı döndürdü."
        }
    }
}

/// Reads `/me/calendarView` (following `@odata.nextLink`) and `/me`.
struct MicrosoftGraphCalendarClient: Sendable {
    static let graphHost = "graph.microsoft.com"
    static let calendarViewPath = "/v1.0/me/calendarView"
    static let mePath = "/v1.0/me"
    static let selectFields = "subject,start,end,isAllDay,location,onlineMeeting,onlineMeetingUrl,bodyPreview,body,webLink,isCancelled"
    static let preferHeader = #"outlook.timezone="UTC", outlook.body-content-type="text""#
    static let pageSize = 100
    static let maxPages = 20

    let http: any CalendarHTTPClient

    func calendarView(accessToken: String, from start: Date, to end: Date) async throws -> [MicrosoftGraphEvent] {
        guard var next = calendarViewURL(from: start, to: end) else { throw MicrosoftGraphError.invalidResponse }
        var events: [MicrosoftGraphEvent] = []
        for _ in 0..<Self.maxPages {
            let page: MicrosoftGraphEventPage = try await get(next, accessToken: accessToken)
            events += page.value
            guard let link = page.nextLink else { return events }
            guard let url = URL(string: link), Self.isTrusted(url) else { throw MicrosoftGraphError.untrustedNextLink }
            next = url
        }
        return events
    }

    /// Display name for settings: UPN / mail, else display name.
    func userName(accessToken: String) async throws -> String? {
        var components = baseComponents(path: Self.mePath)
        components.queryItems = [URLQueryItem(name: "$select", value: "displayName,userPrincipalName,mail")]
        guard let url = components.url else { throw MicrosoftGraphError.invalidResponse }
        let user: MicrosoftGraphUser = try await get(url, accessToken: accessToken)
        return user.mail ?? user.userPrincipalName ?? user.displayName
    }

    func calendarViewURL(from start: Date, to end: Date) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        var components = baseComponents(path: Self.calendarViewPath)
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: formatter.string(from: start)),
            URLQueryItem(name: "endDateTime", value: formatter.string(from: end)),
            URLQueryItem(name: "$select", value: Self.selectFields),
            URLQueryItem(name: "$top", value: String(Self.pageSize)),
        ]
        return components.url
    }

    // MARK: - Private

    /// The bearer token is only ever sent to graph.microsoft.com over https.
    static func isTrusted(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == graphHost
    }

    private func baseComponents(path: String) -> URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.graphHost
        components.path = path
        return components
    }

    private func get<Response: Decodable>(_ url: URL, accessToken: String) async throws -> Response {
        guard Self.isTrusted(url) else { throw MicrosoftGraphError.untrustedNextLink }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.preferHeader, forHTTPHeaderField: "Prefer")
        let (data, response) = try await http.data(for: request)
        switch response.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw MicrosoftGraphError.invalidResponse
            }
        case 401:
            throw MicrosoftGraphError.unauthorized
        default:
            throw MicrosoftGraphError.http(response.statusCode)
        }
    }
}
