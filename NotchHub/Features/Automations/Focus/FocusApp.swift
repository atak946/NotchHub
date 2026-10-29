import Foundation

/// An app on the Focus Guard distraction list.
struct FocusApp: Codable, Hashable, Identifiable, Sendable {
    let bundleID: String
    let name: String
    /// Disabled entries stay in the list (e.g. Slack) but never trigger a reminder.
    var isEnabled: Bool

    var id: String { bundleID.lowercased() }

    init(bundleID: String, name: String, isEnabled: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.isEnabled = isEnabled
    }

    /// Chat apps are watched by default; Slack is listed but off; browsers are not listed at all.
    static let defaults: [FocusApp] = [
        FocusApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
        FocusApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
        FocusApp(bundleID: "org.telegram.desktop", name: "Telegram Desktop"),
        FocusApp(bundleID: "com.hnc.Discord", name: "Discord"),
        FocusApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", isEnabled: false),
    ]
}

/// Pure helpers over the distraction list.
enum FocusAppList {
    /// Bundle IDs (lower-cased) that currently trigger reminders.
    static func activeIDs(in apps: [FocusApp]) -> Set<String> {
        Set(apps.filter(\.isEnabled).map(\.id))
    }

    static func matches(_ bundleID: String?, in activeIDs: Set<String>) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return activeIDs.contains(bundleID.lowercased())
    }

    /// Appends `app` unless its bundle ID is already listed (case-insensitive).
    static func adding(_ app: FocusApp, to apps: [FocusApp]) -> [FocusApp] {
        guard !app.bundleID.isEmpty, !apps.contains(where: { $0.id == app.id }) else { return apps }
        return apps + [app]
    }

    static func removing(_ id: FocusApp.ID, from apps: [FocusApp]) -> [FocusApp] {
        apps.filter { $0.id != id }
    }

    static func setting(_ id: FocusApp.ID, enabled: Bool, in apps: [FocusApp]) -> [FocusApp] {
        apps.map { app in
            guard app.id == id else { return app }
            var updated = app
            updated.isEnabled = enabled
            return updated
        }
    }

    static func decode(_ data: Data?) -> [FocusApp]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([FocusApp].self, from: data)
    }

    static func encode(_ apps: [FocusApp]) -> Data? {
        try? JSONEncoder().encode(apps)
    }
}
