import Foundation
import Synchronization
@testable import NotchHub

/// Mutable clock that can be shared with the `@Sendable` `now` closure.
final class CalendarTestClock: Sendable {
    private let storage: Mutex<Date>

    init(_ date: Date) {
        storage = Mutex(date)
    }

    var now: Date {
        storage.withLock { $0 }
    }

    func set(_ date: Date) {
        storage.withLock { $0 = date }
    }

    func advance(by interval: TimeInterval) {
        storage.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

@MainActor
final class FakeCalendarSource: CalendarEventSource {
    var sourceID = "fake"
    var sourceName = "Fake"
    var statusMessage: String?
    /// When set, `events(from:to:)` throws it.
    var failure: (any Error)?
    var authorization: CalendarAuthorization
    var grantOnRequest = true
    var storedEvents: [CalendarEvent] = []
    var storedAccounts: [CalendarAccount] = []
    var storedCalendars: [CalendarInfo] = []
    private(set) var requestCount = 0
    private(set) var changeHandler: (@MainActor () -> Void)?

    init(authorization: CalendarAuthorization = .authorized) {
        self.authorization = authorization
    }

    func requestAccess() async -> CalendarAuthorization {
        requestCount += 1
        if authorization == .notDetermined {
            authorization = grantOnRequest ? .authorized : .denied
        }
        return authorization
    }

    func accounts() -> [CalendarAccount] { storedAccounts }
    func calendars() -> [CalendarInfo] { storedCalendars }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        if let failure { throw failure }
        return storedEvents.filter { $0.start < end && $0.end > start }
    }

    func startObservingChanges(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler
    }

    func stopObservingChanges() {
        changeHandler = nil
    }

    func simulateStoreChange() {
        changeHandler?()
    }
}

enum CalendarFixtures {
    static let calendar = Calendar.current

    /// Today at the given wall-clock time (fixed day so tests are stable).
    static func date(hour: Int, minute: Int = 0, second: Int = 0, dayOffset: Int = 0) -> Date {
        let components = DateComponents(year: 2026, month: 3, day: 10 + dayOffset, hour: hour, minute: minute, second: second)
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static let outlook = CalendarAccount(id: "src-outlook", title: "Work (Outlook)", kind: .outlook)
    static let google = CalendarAccount(id: "src-google", title: "me@gmail.com", kind: .google)
    static let iCloud = CalendarAccount(id: "src-icloud", title: "iCloud", kind: .iCloud)

    static func link(_ provider: MeetingProvider) -> MeetingLink {
        MeetingLink(provider: provider, url: URL(string: "https://example.com/\(provider.rawValue)") ?? URL(fileURLWithPath: "/"))
    }

    static func event(
        _ id: String,
        start: Date,
        minutes: Int = 30,
        isAllDay: Bool = false,
        calendarID: String = "cal-work",
        account: CalendarAccount = outlook,
        link: MeetingLink? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: isAllDay,
            meetingLink: link,
            calendarID: calendarID,
            calendarTitle: calendarID,
            account: account
        )
    }

    static func makeDefaults() -> UserDefaults {
        let suiteName = "NotchHubTests.Calendar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
