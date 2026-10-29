import Foundation

/// What was going on when a note was created.
struct NoteContext: Equatable, Sendable {
    var meetingTitle: String?
    var clientName: String?

    static let none = NoteContext()
}

/// Reads the in-progress meeting (Calendar) and the active client profile (Profiles).
@MainActor
struct LiveNoteContextProvider {
    let calendar: CalendarService
    let profiles: ProfilesStore

    func context(at date: Date) -> NoteContext {
        NoteContext(
            meetingTitle: Self.meetingTitle(in: calendar.todayEvents + [calendar.nextEvent].compactMap { $0 }, at: date),
            clientName: profiles.activeProfile?.displayName
        )
    }

    /// Title of the first timed event in progress at `date`, if any.
    nonisolated static func meetingTitle(in events: [CalendarEvent], at date: Date) -> String? {
        events
            .first { !$0.isAllDay && $0.isInProgress(at: date) }
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}
