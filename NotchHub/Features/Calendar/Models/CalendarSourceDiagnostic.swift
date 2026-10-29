import Foundation

/// Per-source summary shown in settings and the module so users can see where meetings come from.
struct CalendarSourceDiagnostic: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let isActive: Bool
    let eventsToday: Int
    let message: String?

    /// e.g. "3 events today", "Bağlı değil", "1 event today · Sync failed".
    var summary: String {
        guard isActive else { return message ?? String(localized: "Bağlı değil") }
        let count = String(localized: "Bugün \(eventsToday) etkinlik")
        guard let message else { return count }
        return "\(count) · \(message)"
    }
}
