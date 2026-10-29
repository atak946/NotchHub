import Foundation

/// Decides from Info.plist whether Sparkle may run. Dev and fork builds leave the feed and key empty,
/// so they never start the updater.
struct UpdaterConfiguration: Equatable, Sendable {
    static let feedURLKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"
    private static let requiredScheme = "https"
    /// An unexpanded build setting such as `$(SU_FEED_URL)` means the value was never configured.
    private static let unexpandedPrefix = "$("

    let feedURL: URL?
    let hasPublicKey: Bool

    init(infoDictionary: [String: Any]) {
        feedURL = Self.value(Self.feedURLKey, in: infoDictionary).flatMap(Self.secureURL)
        hasPublicKey = Self.value(Self.publicKeyKey, in: infoDictionary) != nil
    }

    static var current: UpdaterConfiguration {
        UpdaterConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    var isConfigured: Bool {
        feedURL != nil && hasPublicKey
    }

    private static func value(_ key: String, in info: [String: Any]) -> String? {
        guard let raw = info[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(unexpandedPrefix) else { return nil }
        return trimmed
    }

    private static func secureURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == requiredScheme,
              url.host?.isEmpty == false
        else { return nil }
        return url
    }
}

/// "1.2.0 (2)" from the bundle's marketing and build versions.
enum AppVersion {
    static func text(infoDictionary: [String: Any]) -> String {
        let marketing = infoDictionary["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = infoDictionary["CFBundleVersion"] as? String, !build.isEmpty else { return marketing }
        return "\(marketing) (\(build))"
    }

    static var current: String {
        text(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }
}
