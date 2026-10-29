import Foundation

/// Builds the prefilled GitHub "new issue" link from the `NHIssueURL` Info.plist value.
enum DiagnosticsIssueURL {
    static let infoPlistKey = "NHIssueURL"
    /// GitHub and browsers truncate long URLs; the full report goes through the clipboard instead.
    static let maxLength = 6 * 1024
    static var defaultTitle: String { String(localized: "Sorun: ") }
    static var pasteInstruction: String { String(localized: "Tam tanılama raporu panoya kopyalandı; lütfen buraya yapıştır (⌘V).") }
    static let truncationMarker = "…"

    private static let githubHost = "https://github.com/"
    private static let newIssuePath = "/issues/new"
    private static let slugPattern = #"^[A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-]+$"#
    /// RFC 3986 unreserved characters; everything else (including `+` and `&`) is percent-encoded.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Accepts `owner/repo` or an `https://` repository / new-issue URL. Empty or unexpanded values yield `nil`.
    static func baseURL(from configured: String?) -> URL? {
        let value = (configured ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        if value.range(of: slugPattern, options: .regularExpression) != nil {
            return URL(string: githubHost + value + newIssuePath)
        }
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.query == nil
        else { return nil }
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let issuePath = path.hasSuffix(newIssuePath) ? path : path + newIssuePath
        return URL(string: "https://\(host)\(issuePath)")
    }

    static func body(summary: String, instruction: String = pasteInstruction) -> String {
        "\(instruction)\n\n```\n\(summary)\n```\n"
    }

    /// The issue URL with title and body, trimmed so `absoluteString` never exceeds `maxLength` bytes.
    static func make(base: URL, title: String = defaultTitle, summary: String, instruction: String = pasteInstruction) -> URL? {
        var lines = summary.components(separatedBy: "\n")
        while true {
            let candidate = url(base: base, title: title, body: body(summary: lines.joined(separator: "\n"), instruction: instruction))
            if let candidate, candidate.absoluteString.utf8.count <= maxLength {
                return candidate
            }
            guard !lines.isEmpty else { break }
            lines.removeLast()
            if lines.isEmpty { break }
            lines[lines.count - 1] += truncationMarker
        }
        // Even an empty summary does not fit (absurd title): fall back to the instruction alone.
        let minimal = url(base: base, title: defaultTitle, body: instruction)
        return minimal.flatMap { $0.absoluteString.utf8.count <= maxLength ? $0 : nil }
    }

    private static func url(base: URL, title: String, body: String) -> URL? {
        URL(string: "\(base.absoluteString)?title=\(encode(title))&body=\(encode(body))")
    }

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
