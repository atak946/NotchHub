import Foundation

/// What the closed-notch unread indicator shows: up to two busiest apps, an overflow count and a tooltip.
struct CompactUnreadSummary: Equatable, Sendable {
    static let maxIcons = 2
    static let maxBadgeCount = 99

    /// Busiest first; at most `maxIcons`.
    let shown: [UnreadAppCount]
    /// Apps with unread messages beyond `shown` ("+N").
    let overflow: Int
    /// "WhatsApp: 1, Zoom: 2" in watched-list order.
    let tooltip: String

    init(counts: [UnreadAppCount]) {
        let unread = counts.filter { $0.count > 0 }
        let busiest = unread.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map(\.element)
        shown = Array(busiest.prefix(Self.maxIcons))
        overflow = max(0, unread.count - Self.maxIcons)
        tooltip = unread
            .map { "\(UnreadBadgeMonitor.displayName(for: $0.app)): \($0.count)" }
            .joined(separator: ", ")
    }

    var isEmpty: Bool { shown.isEmpty }

    static func badgeText(for count: Int) -> String {
        count > maxBadgeCount ? "\(maxBadgeCount)+" : "\(count)"
    }
}
