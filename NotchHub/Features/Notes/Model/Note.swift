import Foundation

/// One plain-text note. Kept locally in `notes.json`; never synced.
struct Note: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var body: String
    let createdAt: Date
    var updatedAt: Date
    /// Title of the calendar event that was in progress when the note was created.
    var meetingTitle: String?
    /// Name of the client profile that was active when the note was created.
    var clientName: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        body: String = "",
        createdAt: Date,
        updatedAt: Date? = nil,
        meetingTitle: String? = nil,
        clientName: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.meetingTitle = meetingTitle
        self.clientName = clientName
        self.isPinned = isPinned
    }
}

// MARK: - Title

extension Note {
    static var untitled: String { String(localized: "Yeni not") }

    /// First non-empty line; for an empty meeting note "Toplantı: <title> · <HH:mm>"; otherwise "Yeni not".
    func displayTitle(timeZone: TimeZone = .current) -> String {
        if let firstLine = Self.firstNonEmptyLine(of: body) {
            return firstLine
        }
        if let meetingTitle = meetingTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !meetingTitle.isEmpty {
            let time = Self.timeText(createdAt, timeZone: timeZone)
            return String(localized: "Toplantı: \(meetingTitle) · \(time)")
        }
        return Self.untitled
    }

    static func firstNonEmptyLine(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    static func timeText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Ordering

extension Note {
    /// Pinned notes first, then most recently updated; ties broken by creation date and id for stability.
    static func displayOrder(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
