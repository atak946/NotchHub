import Foundation

/// One macOS notification banner read from Notification Center via Accessibility.
struct NotificationBanner: Identifiable, Equatable, Sendable {
    let id: String
    /// Localized app name, e.g. "WhatsApp" or "Betik Düzenleyici".
    let app: String
    let title: String
    let subtitle: String?
    let body: String?
}

/// Raw AX values of a banner element before parsing (all optional: AX is external input).
struct RawNotificationBanner: Equatable, Sendable {
    var identifier: String?
    var description: String?
    var title: String?
    var subtitle: String?
    var body: String?
}

/// One read of Notification Center: on-screen banners, and whether its banner window exists at all
/// (it only does while a banner is visible, which lets the mirror poll fast only then).
struct NotificationCenterSnapshot: Equatable, Sendable {
    let banners: [NotificationBanner]
    let hasBannerWindow: Bool

    static let empty = NotificationCenterSnapshot(banners: [], hasBannerWindow: false)
}

/// Who sent a message and its text, after splitting group-style "Name: message" bodies.
struct NotificationSender: Equatable, Sendable {
    let name: String
    let message: String?
}

/// Pure parsing of banner AX values; no AX calls here so everything is unit-testable.
enum NotificationBannerParser {
    /// Hard cap per field so a hostile or runaway notification can never bloat memory or the UI.
    static let maxFieldLength = 500
    /// Group senders are short names; longer prefixes are treated as ordinary text ("Not: …").
    static let maxSenderLength = 40
    static let maxSenderWords = 4
    static let senderSeparator = ": "
    static let groupSeparator = " · "

    /// "WhatsApp, Ahmet Yılmaz, Test, Merhaba" → "WhatsApp".
    static func appName(fromDescription description: String?) -> String? {
        guard let first = description?.split(separator: ",", maxSplits: 1).first else { return nil }
        return clean(String(first))
    }

    static func banner(from raw: RawNotificationBanner) -> NotificationBanner? {
        guard let app = appName(fromDescription: raw.description) else { return nil }
        let title = clean(raw.title) ?? fallbackTitle(fromDescription: raw.description)
        let body = clean(raw.body)
        guard let id = clean(raw.identifier) ?? clean(raw.description) else { return nil }
        guard title != nil || body != nil else { return nil }
        return NotificationBanner(id: id, app: app, title: title ?? "", subtitle: clean(raw.subtitle), body: body)
    }

    /// Group chats put the group in the title and "Sender: text" in the body; that becomes
    /// "Sender · Group" with the text alone. Otherwise the title is the sender.
    static func sender(of banner: NotificationBanner) -> NotificationSender {
        let title = banner.title
        if let body = banner.body, let split = splitSenderPrefix(body) {
            let name = title.isEmpty || title == split.name ? split.name : split.name + groupSeparator + title
            return NotificationSender(name: name, message: split.message)
        }
        return NotificationSender(name: title, message: banner.body ?? banner.subtitle)
    }

    /// "Ahmet: Toplantı?" → ("Ahmet", "Toplantı?"); nil when there is no short name prefix.
    static func splitSenderPrefix(_ text: String) -> (name: String, message: String)? {
        guard let range = text.range(of: senderSeparator) else { return nil }
        let name = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let message = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !message.isEmpty, name.count <= maxSenderLength,
              name.split(separator: " ").count <= maxSenderWords,
              !name.contains("://"), !name.allSatisfy({ $0.isNumber })
        else { return nil }
        return (name, message)
    }

    /// Localized names of the banner's custom close action ("Name:Kapat\nTarget:…" on a Turkish system).
    static let closeActionNames = ["kapat", "close", "dismiss", "clear", "temizle", "schließen", "fermer", "cerrar"]
    static let customActionPrefix = "Name:"

    /// Picks the close/dismiss action from `AXUIElementCopyActionNames`; nil when there is none.
    static func closeActionName(from actions: [String]) -> String? {
        actions.first { action in
            guard action.hasPrefix(customActionPrefix) else { return false }
            let name = action.dropFirst(customActionPrefix.count)
                .prefix { $0 != "\n" }
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            return closeActionNames.contains(name)
        }
    }

    /// Trims, collapses whitespace/newlines to single spaces and caps length; empty → nil.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxFieldLength))
    }

    /// Without a title child, the second description component is the title.
    private static func fallbackTitle(fromDescription description: String?) -> String? {
        let parts = description?.split(separator: ",", maxSplits: 2) ?? []
        return parts.count > 1 ? clean(String(parts[1])) : nil
    }
}
