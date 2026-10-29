import Foundation

/// Pure scrubbing of personal data from diagnostics text before it leaves the Mac.
enum DiagnosticsRedactor {
    static let emailPlaceholder = "<email>"
    static let queryPlaceholder = "<query>"
    static let ipPlaceholder = "<ip>"
    static let hexPlaceholder = "<hex>"
    static let tokenPlaceholder = "<token>"
    static let homePlaceholder = "~"

    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let template: String
    }

    /// Applied in order: URL queries go first so tokens inside them collapse into one placeholder.
    private static let rules: [Rule] = [
        rule(#"([A-Za-z][A-Za-z0-9+.\-]*://[^\s?#]*)\?[^\s#]*"#, "$1?\(queryPlaceholder)"),
        rule(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, emailPlaceholder),
        rule(#"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])"#, ipPlaceholder),
        rule(#"(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{1,4}:){4,7}[0-9A-Fa-f]{1,4}(?![0-9A-Za-z:])"#, ipPlaceholder),
        rule(#"(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{1,4}:){1,6}:(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){0,5})?(?![0-9A-Za-z:])"#, ipPlaceholder),
        rule(#"\b[0-9A-Fa-f]{16,}\b"#, hexPlaceholder),
        rule(#"(?<![A-Za-z0-9_\-])(?=[A-Za-z_\-]*[0-9])(?=[0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{32,}(?![A-Za-z0-9_\-])"#, tokenPlaceholder),
    ]

    private static let usersPath = rule(#"/Users/[^/\s]+"#, homePlaceholder)

    private static func rule(_ pattern: String, _ template: String) -> Rule {
        do {
            return Rule(regex: try NSRegularExpression(pattern: pattern), template: template)
        } catch {
            preconditionFailure("Invalid redaction pattern \(pattern): \(error)")
        }
    }

    /// Runs every redaction. `homeDirectory` is `NSHomeDirectory()` in production.
    static func redact(_ text: String, homeDirectory: String = NSHomeDirectory()) -> String {
        let withoutHome = redactHomePath(text, homeDirectory: homeDirectory)
        return rules.reduce(withoutHome) { partial, rule in
            replace(rule, in: partial)
        }
    }

    /// Replaces the user's home folder with `~`, plus any other `/Users/<name>` prefix.
    static func redactHomePath(_ text: String, homeDirectory: String) -> String {
        let trimmedHome = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        let withoutHome = trimmedHome.count > 1
            ? text.replacingOccurrences(of: trimmedHome, with: homePlaceholder)
            : text
        return replace(usersPath, in: withoutHome)
    }

    static func redactEmails(_ text: String) -> String { replace(rules[1], in: text) }
    static func redactURLQueries(_ text: String) -> String { replace(rules[0], in: text) }
    static func redactIPAddresses(_ text: String) -> String {
        [rules[2], rules[3], rules[4]].reduce(text) { replace($1, in: $0) }
    }
    static func redactTokens(_ text: String) -> String {
        [rules[5], rules[6]].reduce(text) { replace($1, in: $0) }
    }

    private static func replace(_ rule: Rule, in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return rule.regex.stringByReplacingMatches(in: text, range: range, withTemplate: rule.template)
    }
}
