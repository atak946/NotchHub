import Foundation

/// Finds video-meeting links in event fields. Pure and side-effect free.
enum MeetingLinkParser {
    /// A URL with a scheme, or a scheme-less link on a known meeting host (common in Outlook locations).
    private static let candidatePattern =
        #"(?i)(?:(?:https?|zoommtg)://|\b(?:[a-z0-9-]+\.)*(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com)/)[^\s<>"'\[\]]+"#
    private static let trailingJunk = CharacterSet(charactersIn: ".,;:!?)]}>'\"*")
    private static let safelinksHostSuffix = "safelinks.protection.outlook.com"
    private static let safelinksQueryName = "url"
    private static let maxUnwrapDepth = 3
    private static let defaultScheme = "https://"
    private static let supportedSchemes: Set<String> = ["http", "https", "zoommtg"]

    private static let zoomDomain = "zoom.us"
    private static let zoomScheme = "zoommtg"
    private static let zoomMeetingPathPrefixes = ["/j/", "/w/", "/my/", "/s/"]
    private static let zoomJoinPathPrefix = "/j/"
    private static let teamsBusinessHost = "teams.microsoft.com"
    private static let teamsBusinessPathPrefixes = ["/l/meetup-join", "/meet/"]
    private static let teamsConsumerHost = "teams.live.com"
    private static let meetHost = "meet.google.com"
    private static let webexDomain = "webex.com"
    private static let otherMeetingDomains = [
        "gotomeeting.com", "gotomeet.me", "chime.aws", "bluejeans.com", "whereby.com", "meet.jit.si", "around.co",
    ]

    /// Detects a meeting link, preferring the event URL, then the location, then the notes.
    static func parse(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = firstLink(in: url.absoluteString) {
            return link
        }
        if let location, let link = firstLink(in: location) {
            return link
        }
        if let notes, let link = firstLink(in: notes) {
            return link
        }
        return nil
    }

    /// The URL to open for a link: Zoom meetings go straight to the Zoom app when it is installed.
    static func launchURL(for link: MeetingLink, isZoomAppInstalled: Bool) -> URL {
        guard link.provider == .zoom, isZoomAppInstalled, let appURL = zoomAppURL(from: link.url) else {
            return link.url
        }
        return appURL
    }

    /// Converts `https://<sub>.zoom.us/j/<id>?pwd=…` into `zoommtg://<host>/join?action=join&confno=<id>&pwd=…`.
    static func zoomAppURL(from url: URL) -> URL? {
        if url.scheme?.lowercased() == zoomScheme {
            return url
        }
        guard
            let host = url.host()?.lowercased(),
            matches(host: host, domain: zoomDomain),
            url.path().hasPrefix(zoomJoinPathPrefix)
        else { return nil }

        let meetingID = String(url.path().dropFirst(zoomJoinPathPrefix.count)).trimmingCharacters(in: .init(charactersIn: "/"))
        guard !meetingID.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = zoomScheme
        components.host = host
        components.path = "/join"
        let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "pwd" }?.value
        components.queryItems = [
            URLQueryItem(name: "action", value: "join"),
            URLQueryItem(name: "confno", value: meetingID),
        ] + (password.map { [URLQueryItem(name: "pwd", value: $0)] } ?? [])
        return components.url
    }

    // MARK: - Scanning

    private static func firstLink(in text: String) -> MeetingLink? {
        guard let regex = try? Regex(candidatePattern) else { return nil }
        for match in text.matches(of: regex) {
            if let link = link(fromCandidate: String(text[match.range]), depth: 0) {
                return link
            }
        }
        return nil
    }

    private static func link(fromCandidate candidate: String, depth: Int) -> MeetingLink? {
        guard depth <= maxUnwrapDepth, let url = normalizedURL(candidate) else { return nil }
        if let inner = unwrappedSafelink(url) {
            return link(fromCandidate: inner, depth: depth + 1)
        }
        return classify(url).map { MeetingLink(provider: $0, url: url) }
    }

    private static func normalizedURL(_ candidate: String) -> URL? {
        var trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.unicodeScalars.last, trailingJunk.contains(last) {
            trimmed.removeLast()
        }
        if trimmed.hasPrefix("<") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : defaultScheme + trimmed
        guard
            let url = URL(string: withScheme),
            let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme),
            let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private static func unwrappedSafelink(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased(), host.hasSuffix(safelinksHostSuffix) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name.lowercased() == safelinksQueryName }?.value
    }

    // MARK: - Classification

    private static func classify(_ url: URL) -> MeetingProvider? {
        if url.scheme?.lowercased() == zoomScheme {
            return .zoom
        }
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.path().lowercased()
        let hasPath = path.count > 1

        if matches(host: host, domain: zoomDomain) {
            return zoomMeetingPathPrefixes.contains(where: path.hasPrefix) ? .zoom : nil
        }
        if host == teamsBusinessHost {
            return teamsBusinessPathPrefixes.contains(where: path.hasPrefix) ? .teams : nil
        }
        if host == teamsConsumerHost {
            return hasPath ? .teams : nil
        }
        if host == meetHost {
            return hasPath ? .meet : nil
        }
        if matches(host: host, domain: webexDomain) {
            return hasPath ? .webex : nil
        }
        if otherMeetingDomains.contains(where: { matches(host: host, domain: $0) }) {
            return hasPath ? .other : nil
        }
        return nil
    }

    private static func matches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
