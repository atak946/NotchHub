import Foundation

/// Per-app choice for showing the text of mirrored notifications.
enum NotificationContentVisibility: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Follows the global "Mesaj içeriğini göster" toggle.
    case followsGlobal
    case shown
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followsGlobal: String(localized: "Varsayılan")
        case .shown: String(localized: "İçeriği göster")
        case .hidden: String(localized: "İçeriği gizle")
        }
    }

    func showsContent(globalShowsText: Bool) -> Bool {
        switch self {
        case .followsGlobal: globalShowsText
        case .shown: true
        case .hidden: false
        }
    }
}

/// An app that produced (or may produce) mirrored notifications.
/// Identified by bundle id when known, otherwise by its normalized name.
struct NotificationAppIdentity: Codable, Hashable, Identifiable, Sendable {
    static let maxNameLength = 80

    let bundleID: String?
    let name: String

    /// `nil` when the name is empty; invalid bundle ids are dropped (they come from external input).
    init?(bundleID: String?, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.bundleID = Self.validBundleID(bundleID)
        self.name = String(trimmed.prefix(Self.maxNameLength))
    }

    static let maxBundleIDLength = 255

    /// Reverse-DNS characters only; anything else is treated as "no bundle id".
    static func validBundleID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= maxBundleIDLength
        else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : nil
    }

    var id: String { key }

    /// The storage key: `bundle:<id>` when the bundle id is known, else `name:<normalized name>`.
    var key: String { bundleKey ?? nameKey }

    var bundleKey: String? { bundleID.map { "bundle:" + $0.lowercased() } }

    var nameKey: String { "name:" + Self.normalizedName(name) }

    /// Same bundle id when both sides know one; otherwise the same normalized name.
    func matches(_ other: NotificationAppIdentity) -> Bool {
        if let mine = bundleKey, let theirs = other.bundleKey { return mine == theirs }
        return nameKey == other.nameKey
    }

    /// "Zoom Workplace" and "zoom.us" both become "zoom"; case and diacritics are ignored.
    static func normalizedName(_ name: String) -> String {
        MessagingApp.canonicalKey(for: name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// A non-default per-app choice.
struct NotificationPrivacyRule: Codable, Equatable, Sendable {
    let app: NotificationAppIdentity
    let visibility: NotificationContentVisibility
}

/// Pure resolution of per-app content visibility and the recent-apps list.
enum NotificationPrivacyPolicy {
    static let maxRecentApps = 20

    /// A rule with the same bundle id wins over a rule that only matches by name.
    static func visibility(
        for app: NotificationAppIdentity, rules: [NotificationPrivacyRule]
    ) -> NotificationContentVisibility {
        let byBundle = rules.first { rule in
            guard let key = app.bundleKey else { return false }
            return rule.app.bundleKey == key
        }
        let match = byBundle ?? rules.first { $0.app.matches(app) }
        return match?.visibility ?? .followsGlobal
    }

    static func showsContent(
        for app: NotificationAppIdentity, rules: [NotificationPrivacyRule], globalShowsText: Bool
    ) -> Bool {
        visibility(for: app, rules: rules).showsContent(globalShowsText: globalShowsText)
    }

    /// Replaces any rule for the same app; `.followsGlobal` just removes it.
    static func setting(
        _ visibility: NotificationContentVisibility, for app: NotificationAppIdentity, in rules: [NotificationPrivacyRule]
    ) -> [NotificationPrivacyRule] {
        let others = rules.filter { !$0.app.matches(app) }
        guard visibility != .followsGlobal else { return others }
        return others + [NotificationPrivacyRule(app: app, visibility: visibility)]
    }

    /// Moves the app to the front (most recent first), de-duplicated and capped.
    /// A bundle id learned earlier is kept when the new sighting only knows the name.
    static func recording(
        _ app: NotificationAppIdentity, in recents: [NotificationAppIdentity], capacity: Int = maxRecentApps
    ) -> [NotificationAppIdentity] {
        let previous = recents.first { $0.matches(app) }
        let merged = NotificationAppIdentity(bundleID: app.bundleID ?? previous?.bundleID, name: app.name) ?? app
        let others = recents.filter { !$0.matches(merged) && !$0.matches(app) }
        return Array(([merged] + others).prefix(max(capacity, 1)))
    }

    /// Recent apps first, then apps that only have a rule (so no rule is ever invisible in Settings).
    static func listedApps(
        recents: [NotificationAppIdentity], rules: [NotificationPrivacyRule]
    ) -> [NotificationAppIdentity] {
        let ruleOnly = rules.map(\.app).filter { app in !recents.contains { $0.matches(app) } }
        return recents + ruleOnly
    }
}
