import Foundation

/// Bundle identifiers of well-known apps, looked up by display or Dock name (case-insensitive, exact).
/// Exact names on purpose: "Mail" must not match "Gmail".
enum KnownApps {
    private static let bundleIDs: [String: String] = [
        "whatsapp": "net.whatsapp.WhatsApp",
        "zoom": "us.zoom.xos",
        "zoom.us": "us.zoom.xos",
        "zoom workplace": "us.zoom.xos",
        "outlook": "com.microsoft.Outlook",
        "microsoft outlook": "com.microsoft.Outlook",
        "teams": "com.microsoft.teams2",
        "microsoft teams": "com.microsoft.teams2",
        "slack": "com.tinyspeck.slackmacgap",
        "mail": "com.apple.mail",
        "messages": "com.apple.MobileSMS",
        "mesajlar": "com.apple.MobileSMS",
    ]

    static func bundleID(forName name: String) -> String? {
        bundleIDs[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}
