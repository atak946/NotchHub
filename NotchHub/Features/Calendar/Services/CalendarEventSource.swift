import Foundation

/// Abstraction over one calendar backend (EventKit, ICS feeds, Microsoft Graph) so `CalendarService`
/// can aggregate several of them and stay testable without EventKit or the network.
@MainActor
protocol CalendarEventSource: AnyObject {
    /// Stable identifier used for diagnostics.
    var sourceID: String { get }
    /// Short name shown in settings diagnostics, e.g. "macOS Calendar".
    var sourceName: String { get }
    var sourceSystemImage: String { get }
    /// Last problem worth showing to the user (sync failure, expired session), or nil.
    var statusMessage: String? { get }

    /// `.authorized` when the source can deliver events (permission granted / feed configured / signed in).
    var authorization: CalendarAuthorization { get }

    /// Asks the user for access (no-op when already decided or not applicable) and returns the resulting state.
    func requestAccess() async -> CalendarAuthorization

    func accounts() -> [CalendarAccount]
    func calendars() -> [CalendarInfo]

    /// All event occurrences overlapping `[start, end)`, across every calendar of this source.
    /// Remote sources answer from their last successful sync; throwing marks the source as failing.
    func events(from start: Date, to end: Date) throws -> [CalendarEvent]

    /// Calls `handler` on the main actor whenever the underlying data changes. Remote sources also start syncing here.
    func startObservingChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObservingChanges()
}

extension CalendarEventSource {
    var sourceID: String { String(describing: type(of: self)) }
    var sourceName: String { "Calendar" }
    var sourceSystemImage: String { "calendar" }
    var statusMessage: String? { nil }
}
