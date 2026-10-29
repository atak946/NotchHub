import Foundation

/// Which banners the mirror takes over.
enum NotificationMirrorScope: String, CaseIterable, Identifiable, Sendable {
    case allApps
    case messagingOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allApps: String(localized: "Tüm uygulamalar")
        case .messagingOnly: String(localized: "Yalnızca mesajlaşma uygulamaları")
        }
    }
}

/// What to do with a banner seen for the first time.
enum NotificationMirrorDecision: Equatable, Sendable {
    /// Leave it alone: own notification, out of scope, or notch alerts are off/paused.
    case ignore
    /// Post a notch alert, then close the macOS banner when `dismissNative`.
    case mirror(dismissNative: Bool)
}

/// Contents of the notch alert for one mirrored banner.
struct MirroredAlertContent: Equatable, Sendable {
    let systemImage: String
    let title: String
    /// The text, a placeholder ("Yeni mesaj") when there is none, or "İçerik gizlendi" when it is hidden.
    let subtitle: String
    /// The hidden text, kept for the alert's "Göster" action; `nil` when shown or when there is none.
    let concealedSubtitle: String?
    let coalescingKey: String
    /// Canonical messaging key when the banner came from a watched messaging app.
    let messagingKey: String?
}

/// Pure decisions of the notification mirror, kept free of AX and alert plumbing for tests.
enum NotificationMirrorPolicy {
    static let defaultKeywords = ["whatsapp", "zoom", "teams", "outlook", "slack"]
    /// Banners of these apps are never mirrored or dismissed (avoids feedback loops with our own notifications).
    static let ownAppNames = ["NotchHub"]
    /// Banners posted by scripts (`osascript display notification`) are attributed to Script Editor;
    /// opening it is meaningless, so those alerts get no "Aç" action.
    static let scriptProxyAppNames = ["Script Editor", "Betik Düzenleyici", "osascript"]
    static let maxSubtitleTextLength = 80
    static let maxTitleLength = 60
    static var newMessageText: String { String(localized: "Yeni mesaj") }
    static var newNotificationText: String { String(localized: "Yeni bildirim") }
    static var hiddenContentText: String { String(localized: "İçerik gizlendi") }
    static let separator = " · "
    private static let ellipsis = "…"

    static func decision(
        for banner: NotificationBanner,
        scope: NotificationMirrorScope,
        keywords: [String],
        canPost: Bool,
        hidesNative: Bool
    ) -> NotificationMirrorDecision {
        guard !isOwnNotification(app: banner.app) else { return .ignore }
        if scope == .messagingOnly, !matches(app: banner.app, keywords: keywords) { return .ignore }
        guard canPost else { return .ignore }
        return .mirror(dismissNative: hidesNative)
    }

    static func isOwnNotification(app: String) -> Bool {
        let names = ownAppNames + [Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String]
            .compactMap { $0 }
        return names.contains { $0.caseInsensitiveCompare(app.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }

    /// Case-insensitive "contains", so "zoom.us" and "Zoom Workplace" both match "zoom".
    static func matches(app: String, keywords: [String]) -> Bool {
        keywords.contains { !$0.isEmpty && app.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static func content(
        for banner: NotificationBanner, keywords: [String], showsMessageText: Bool
    ) -> MirroredAlertContent {
        let appName = MessagingApp.displayName(for: banner.app)
        guard matches(app: banner.app, keywords: keywords) else {
            let text = visibleText(banner.subtitle ?? banner.body, shows: showsMessageText, placeholder: newNotificationText)
            return MirroredAlertContent(
                systemImage: MessagingApp.fallbackSystemImage,
                title: truncated(banner.title.isEmpty ? appName : banner.title, limit: maxTitleLength),
                subtitle: text.subtitle,
                concealedSubtitle: text.concealed,
                coalescingKey: "insights.mirror.\(banner.id)",
                messagingKey: nil
            )
        }
        let sender = NotificationBannerParser.sender(of: banner)
        let key = MessagingApp.canonicalKey(for: banner.app)
        let text = visibleText(sender.message, shows: showsMessageText, placeholder: newMessageText)
        return MirroredAlertContent(
            systemImage: MessagingApp.systemImage(for: banner.app),
            title: truncated(sender.name.isEmpty ? appName : sender.name, limit: maxTitleLength),
            subtitle: text.subtitle,
            concealedSubtitle: text.concealed,
            coalescingKey: "insights.mirror.\(key).\(sender.name.lowercased())",
            messagingKey: key
        )
    }

    /// Shown: the text (or placeholder). Hidden: "İçerik gizlendi" plus the text kept aside for "Göster";
    /// with no text at all there is nothing to hide, so the placeholder is used either way.
    static func visibleText(
        _ text: String?, shows: Bool, placeholder: String
    ) -> (subtitle: String, concealed: String?) {
        let shownSubtitle = subtitle(text: text, placeholder: placeholder)
        guard !shows, NotificationBannerParser.clean(text) != nil else { return (shownSubtitle, nil) }
        return (hiddenContentText, shownSubtitle)
    }

    /// The truncated text, or the placeholder ("Yeni mesaj") when there is none to show.
    /// The app name is not repeated here: the alert shows it as its source label beside the notch.
    static func subtitle(text: String?, placeholder: String) -> String {
        NotificationBannerParser.clean(text).map { truncated($0, limit: maxSubtitleTextLength) } ?? placeholder
    }

    /// Cuts to `limit` characters including a trailing ellipsis.
    static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > ellipsis.count else { return text }
        let head = text.prefix(limit - ellipsis.count).trimmingCharacters(in: .whitespaces)
        return head + ellipsis
    }

    static func canOpen(app: String) -> Bool {
        !scriptProxyAppNames.contains { $0.caseInsensitiveCompare(app) == .orderedSame }
    }

    /// Trimmed, lowercased, de-duplicated keywords; empty entries dropped.
    static func normalizedKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Insertion-ordered id set that forgets the oldest ids beyond `capacity`.
struct BoundedIDSet: Sendable {
    let capacity: Int
    private var order: [String] = []
    private var members: Set<String> = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int { order.count }

    func contains(_ id: String) -> Bool { members.contains(id) }

    /// `true` when the id was new.
    @discardableResult
    mutating func insert(_ id: String) -> Bool {
        guard members.insert(id).inserted else { return false }
        order.append(id)
        if order.count > capacity {
            members.remove(order.removeFirst())
        }
        return true
    }

    mutating func removeAll() {
        order = []
        members = []
    }
}

/// When the mirror last alerted per messaging app, so the Dock badge monitor can skip its duplicate
/// "WhatsApp · 1 yeni" alert. Badge alerts still fire when Focus/DND hides the banners.
@MainActor
final class NotificationMirrorLedger {
    static let suppressionWindow: TimeInterval = 15

    private var lastAlertAt: [String: Date] = [:]

    func record(appKey: String, at date: Date) {
        lastAlertAt[appKey] = date
    }

    func suppressesBadgeAlert(forApp app: String, at now: Date) -> Bool {
        guard let last = lastAlertAt[MessagingApp.canonicalKey(for: app)] else { return false }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= 0 && elapsed < Self.suppressionWindow
    }
}
