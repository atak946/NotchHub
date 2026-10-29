import Foundation

/// Canonical identity of a messaging app, shared by the Dock badge monitor and the notification mirror so
/// "Microsoft Teams" (Dock), "Teams" (banner) and "zoom.us" / "Zoom Workplace" resolve to the same key.
enum MessagingApp {
    private struct Known {
        let key: String
        let displayName: String
        let systemImage: String
    }

    private static let known = [
        Known(key: "whatsapp", displayName: "WhatsApp", systemImage: "message.fill"),
        Known(key: "zoom", displayName: "Zoom", systemImage: "video.fill"),
        Known(key: "teams", displayName: "Teams", systemImage: "person.2.fill"),
        Known(key: "outlook", displayName: "Outlook", systemImage: "envelope.fill"),
        Known(key: "slack", displayName: "Slack", systemImage: "number"),
    ]
    static let fallbackSystemImage = "bell.badge.fill"

    /// whatsapp / zoom / teams / outlook / slack, or the trimmed, lowercased name for anything else.
    static func canonicalKey(for app: String) -> String {
        knownApp(for: app)?.key ?? app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func displayName(for app: String) -> String {
        knownApp(for: app)?.displayName ?? app.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func systemImage(for app: String) -> String {
        knownApp(for: app)?.systemImage ?? fallbackSystemImage
    }

    private static func knownApp(for app: String) -> Known? {
        known.first { app.range(of: $0.key, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
