import Foundation

/// Non-secret metadata of a subscribed ICS feed. The feed URL itself lives in the Keychain under `id`.
struct ICSFeed: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var colorIndex: Int
    /// `CalendarAccountKind.rawValue` derived from the URL host when the feed was added.
    var kindRawValue: String

    var kind: CalendarAccountKind {
        CalendarAccountKind(rawValue: kindRawValue) ?? .other
    }

    var color: CalendarColor {
        Self.palette[abs(colorIndex) % Self.palette.count]
    }

    var accountID: String { "ics.account.\(id)" }
    var calendarID: String { "ics.calendar.\(id)" }

    var account: CalendarAccount {
        CalendarAccount(id: accountID, title: name, kind: kind)
    }

    static let palette: [CalendarColor] = [
        CalendarColor(red: 0.0, green: 0.47, blue: 0.84),
        CalendarColor(red: 0.95, green: 0.55, blue: 0.1),
        CalendarColor(red: 0.2, green: 0.7, blue: 0.4),
        CalendarColor(red: 0.75, green: 0.3, blue: 0.85),
        CalendarColor(red: 0.9, green: 0.3, blue: 0.35),
        CalendarColor(red: 0.3, green: 0.75, blue: 0.8),
    ]
}

/// Validation and normalization of user-entered feed URLs.
enum ICSFeedURL {
    private static let webcalSchemes: Set<String> = ["webcal", "webcals"]
    private static let outlookHosts = ["outlook.office365.com", "outlook.live.com", "outlook.office.com"]

    enum ValidationError: Error, Equatable, LocalizedError {
        case invalid
        case insecure

        var errorDescription: String? {
            switch self {
            case .invalid: String(localized: "Geçerli bir https:// veya webcal:// ICS bağlantısı girin.")
            case .insecure: String(localized: "Yalnızca https:// (veya webcal://) bağlantıları desteklenir.")
            }
        }
    }

    /// `webcal://` → `https://`; only https is accepted because the URL is a credential.
    static func normalized(_ text: String) throws(ValidationError) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased() else {
            throw .invalid
        }
        if webcalSchemes.contains(scheme) {
            components.scheme = "https"
        } else if scheme == "http" {
            throw .insecure
        } else if scheme != "https" {
            throw .invalid
        }
        guard let host = components.host, !host.isEmpty, let url = components.url else { throw .invalid }
        return url
    }

    static func accountKind(for url: URL) -> CalendarAccountKind {
        guard let host = url.host()?.lowercased() else { return .other }
        let isOutlook = outlookHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        return isOutlook ? .outlook : .other
    }
}

/// Persists the feed list (ids, names, colors, kinds only) in `UserDefaults`.
struct ICSFeedStore {
    static let key = "calendar.icsFeeds"

    let defaults: UserDefaults

    func load() -> [ICSFeed] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ICSFeed].self, from: data)) ?? []
    }

    func save(_ feeds: [ICSFeed]) {
        guard let data = try? JSONEncoder().encode(feeds) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Sync state of one feed, shown in settings.
struct ICSFeedStatus: Equatable, Sendable {
    var lastSync: Date?
    var eventCount: Int?
    var errorMessage: String?
}

enum ICSFeedTestResult: Equatable, Sendable {
    case success(eventCount: Int, calendarName: String?)
    case failure(String)

    var message: String {
        switch self {
        case let .success(count, _): String(localized: "Found \(count) events")
        case let .failure(message): message
        }
    }
}
