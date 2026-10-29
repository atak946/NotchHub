import Foundation
import Observation
import OSLog

/// Persisted per-app content visibility for mirrored notifications, plus the recently seen apps.
/// With no stored rules every app follows the global toggle, exactly like before this setting existed.
@MainActor
@Observable
final class NotificationPrivacySettings {
    private enum Keys {
        static let rules = "Insights.mirrorPrivacyRules"
        static let recentApps = "Insights.mirrorRecentApps"
    }

    private(set) var rules: [NotificationPrivacyRule]
    private(set) var recentApps: [NotificationAppIdentity]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = Self.decode([NotificationPrivacyRule].self, from: defaults.data(forKey: Keys.rules)) ?? []
        recentApps = Array(
            (Self.decode([NotificationAppIdentity].self, from: defaults.data(forKey: Keys.recentApps)) ?? [])
                .prefix(NotificationPrivacyPolicy.maxRecentApps)
        )
    }

    /// Apps shown in Settings: recent ones, then any app that only has a rule.
    var listedApps: [NotificationAppIdentity] {
        NotificationPrivacyPolicy.listedApps(recents: recentApps, rules: rules)
    }

    func visibility(for app: NotificationAppIdentity) -> NotificationContentVisibility {
        NotificationPrivacyPolicy.visibility(for: app, rules: rules)
    }

    func showsContent(for app: NotificationAppIdentity, globalShowsText: Bool) -> Bool {
        NotificationPrivacyPolicy.showsContent(for: app, rules: rules, globalShowsText: globalShowsText)
    }

    func setVisibility(_ visibility: NotificationContentVisibility, for app: NotificationAppIdentity) {
        let updated = NotificationPrivacyPolicy.setting(visibility, for: app, in: rules)
        guard updated != rules else { return }
        rules = updated
        save(rules, forKey: Keys.rules)
    }

    /// Called for every mirrored notification and for apps added by hand in Settings.
    func recordSeen(_ app: NotificationAppIdentity) {
        let updated = NotificationPrivacyPolicy.recording(app, in: recentApps)
        guard updated != recentApps else { return }
        recentApps = updated
        save(recentApps, forKey: Keys.recentApps)
    }

    // MARK: - Persistence

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            logger.error("Could not save notification privacy settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Logger(subsystem: AppIdentity.logSubsystem, category: "Insights")
                .error("Ignoring unreadable notification privacy settings: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
