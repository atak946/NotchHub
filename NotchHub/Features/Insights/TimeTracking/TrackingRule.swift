import Foundation

/// User-defined mapping from an activity to a billable client.
struct TrackingRule: Codable, Equatable, Identifiable, Sendable {
    enum MatchType: String, Codable, CaseIterable, Identifiable, Sendable {
        case appBundleID
        case windowTitleContains
        case pathContains

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appBundleID: "Uygulama bundle ID eşittir"
            case .windowTitleContains: "Pencere başlığı içerir"
            case .pathContains: "Belge yolu içerir"
            }
        }

        /// Lower wins: the most specific evidence decides, list order breaks ties.
        var precedence: Int {
            switch self {
            case .pathContains: 0
            case .windowTitleContains: 1
            case .appBundleID: 2
            }
        }
    }

    var id: UUID
    var client: String
    var matchType: MatchType
    var pattern: String

    init(id: UUID = UUID(), client: String, matchType: MatchType, pattern: String) {
        self.id = id
        self.client = client
        self.matchType = matchType
        self.pattern = pattern
    }

    var trimmedClient: String { client.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedPattern: String { pattern.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedClient.isEmpty && !trimmedPattern.isEmpty }
}

/// What the tracker sees at one sample. Titles and paths live only in memory and are never persisted.
struct ActivitySnapshot: Equatable, Sendable {
    var bundleID: String?
    var windowTitle: String?
    var documentPath: String?
    var idleSeconds: TimeInterval
}

enum TrackingRuleMatcher {
    private static let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// First matching rule by (`MatchType.precedence`, list order); `nil` when nothing matches.
    static func matchingRule(for snapshot: ActivitySnapshot, rules: [TrackingRule]) -> TrackingRule? {
        rules.enumerated()
            .filter { $0.element.isValid }
            .sorted { ($0.element.matchType.precedence, $0.offset) < ($1.element.matchType.precedence, $1.offset) }
            .first { matches($0.element, snapshot) }?
            .element
    }

    static func client(for snapshot: ActivitySnapshot, rules: [TrackingRule]) -> String? {
        matchingRule(for: snapshot, rules: rules)?.trimmedClient
    }

    static func matches(_ rule: TrackingRule, _ snapshot: ActivitySnapshot) -> Bool {
        let pattern = rule.trimmedPattern
        switch rule.matchType {
        case .appBundleID:
            return snapshot.bundleID?.caseInsensitiveCompare(pattern) == .orderedSame
        case .windowTitleContains:
            return contains(snapshot.windowTitle, pattern)
        case .pathContains:
            // Many editors (VS Code, terminals) expose no AXDocument but show the path in the title.
            return contains(snapshot.documentPath, pattern) || contains(snapshot.windowTitle, pattern)
        }
    }

    private static func contains(_ text: String?, _ pattern: String) -> Bool {
        guard let text else { return false }
        return text.range(of: pattern, options: compareOptions) != nil
    }
}
