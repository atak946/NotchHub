import AppKit
import EventKit
import OSLog

/// `CalendarEventSource` backed by `EKEventStore`. Every account added in macOS Internet Accounts
/// (Exchange / Office 365, Google CalDAV, iCloud, subscriptions) is aggregated by EventKit.
@MainActor
final class EventKitCalendarSource: CalendarEventSource {
    let sourceID = "eventkit"
    let sourceName = String(localized: "macOS Calendar")
    let sourceSystemImage = "calendar"

    private let store = EKEventStore()
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Calendar")
    private var changeObserver: NSObjectProtocol?
    private static let untitledEventTitle = String(localized: "Untitled event")

    var authorization: CalendarAuthorization {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async -> CalendarAuthorization {
        guard authorization == .notDetermined else { return authorization }
        do {
            let granted = try await requestFullAccess()
            logger.info("Calendar access \(granted ? "granted" : "denied", privacy: .public)")
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
        return authorization
    }

    func accounts() -> [CalendarAccount] {
        let sources = Set(store.calendars(for: .event).map(\.source))
        return sources
            .map(Self.account(for:))
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind.sortOrder < rhs.kind.sortOrder }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    color: Self.color(from: calendar.color),
                    accountID: calendar.source?.sourceIdentifier ?? CalendarAccount.unknown.id
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.event(from:))
    }

    func startObservingChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObservingChanges()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    func stopObservingChanges() {
        guard let changeObserver else { return }
        NotificationCenter.default.removeObserver(changeObserver)
        self.changeObserver = nil
    }

    // MARK: - Private

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> CalendarAuthorization {
        switch status {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    private static func account(for source: EKSource?) -> CalendarAccount {
        guard let source else { return .unknown }
        return CalendarAccount(
            id: source.sourceIdentifier,
            title: source.title,
            kind: CalendarAccountKind.classify(sourceType: source.sourceType, title: source.title)
        )
    }

    private static func event(from event: EKEvent) -> CalendarEvent? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let baseID = event.calendarItemIdentifier
        let rawTitle: String = event.title ?? ""
        let rawLocation: String = event.location ?? ""
        return CalendarEvent(
            id: "\(baseID)@\(Int(start.timeIntervalSince1970))",
            title: rawTitle.isEmpty ? untitledEventTitle : rawTitle,
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            calendarColor: color(from: event.calendar?.color),
            location: rawLocation.isEmpty ? nil : rawLocation,
            meetingLink: MeetingLinkParser.parse(url: event.url, location: event.location, notes: event.notes),
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            account: account(for: event.calendar?.source)
        )
    }

    private static func color(from color: NSColor?) -> CalendarColor {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return .fallback }
        return CalendarColor(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        )
    }
}
