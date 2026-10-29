import Foundation

/// How the today list is grouped.
enum CalendarGrouping: String, CaseIterable, Identifiable, Sendable {
    case none
    case account
    case provider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Tümü"
        case .account: "Hesaba göre"
        case .provider: "Uygulamaya göre"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "list.bullet"
        case .account: "person.crop.circle"
        case .provider: "video"
        }
    }
}

struct CalendarEventGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let events: [CalendarEvent]
}

/// Bucket used when grouping by meeting app.
enum MeetingGroupKind: String, CaseIterable, Sendable {
    case zoom
    case teams
    case meet
    case webex
    case otherLink
    case noLink

    init(link: MeetingLink?) {
        switch link?.provider {
        case .zoom: self = .zoom
        case .teams: self = .teams
        case .meet: self = .meet
        case .webex: self = .webex
        case .other: self = .otherLink
        case nil: self = .noLink
        }
    }

    var title: String {
        switch self {
        case .zoom: MeetingProvider.zoom.displayName
        case .teams: MeetingProvider.teams.displayName
        case .meet: MeetingProvider.meet.displayName
        case .webex: MeetingProvider.webex.displayName
        case .otherLink: "Diğer bağlantı"
        case .noLink: "Yüz yüze / bağlantısız"
        }
    }

    var systemImage: String {
        switch self {
        case .zoom: MeetingProvider.zoom.systemImage
        case .teams: MeetingProvider.teams.systemImage
        case .meet: MeetingProvider.meet.systemImage
        case .webex: MeetingProvider.webex.systemImage
        case .otherLink: MeetingProvider.other.systemImage
        case .noLink: "mappin.and.ellipse"
        }
    }
}

/// Pure grouping of events. Empty groups are never produced.
enum CalendarEventGrouper {
    static let allGroupID = "all"
    static let allGroupTitle = "Bugün"
    static let allGroupImage = "calendar"
    private static let accountPrefix = "account."
    private static let providerPrefix = "provider."

    /// Groups sorted by their earliest event; events inside a group sorted by start time.
    static func groups(for events: [CalendarEvent], by grouping: CalendarGrouping) -> [CalendarEventGroup] {
        guard !events.isEmpty else { return [] }
        switch grouping {
        case .none:
            return [CalendarEventGroup(id: allGroupID, title: allGroupTitle, systemImage: allGroupImage, events: sorted(events))]
        case .account:
            return makeGroups(events, key: \.account) { account, members in
                CalendarEventGroup(
                    id: accountPrefix + account.id,
                    title: account.displayTitle,
                    systemImage: account.kind.systemImage,
                    events: members
                )
            }
        case .provider:
            return makeGroups(events, key: { MeetingGroupKind(link: $0.meetingLink) }) { kind, members in
                CalendarEventGroup(id: providerPrefix + kind.rawValue, title: kind.title, systemImage: kind.systemImage, events: members)
            }
        }
    }

    private static func makeGroups<Key: Hashable>(
        _ events: [CalendarEvent],
        key: (CalendarEvent) -> Key,
        build: (Key, [CalendarEvent]) -> CalendarEventGroup
    ) -> [CalendarEventGroup] {
        Dictionary(grouping: events, by: key)
            .map { build($0.key, sorted($0.value)) }
            .sorted(by: groupPrecedes)
    }

    private static func sorted(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted(by: CalendarSchedule.startsBefore)
    }

    private static func groupPrecedes(_ lhs: CalendarEventGroup, _ rhs: CalendarEventGroup) -> Bool {
        switch (lhs.events.first, rhs.events.first) {
        case let (left?, right?) where left.start != right.start:
            return left.start < right.start
        default:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
