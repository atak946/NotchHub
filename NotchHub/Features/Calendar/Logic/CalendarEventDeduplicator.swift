import Foundation

/// Removes events that several sources report for the same meeting (e.g. an Exchange account in
/// macOS Calendar and the same calendar published as ICS / read via Microsoft Graph).
///
/// Two events are duplicates when their normalized titles match, they start within `startTolerance`,
/// share the all-day flag and their meeting links do not contradict each other (same link, or one side
/// has none — published feeds often drop the link). The richer event wins; ties keep the earlier source.
enum CalendarEventDeduplicator {
    static let startTolerance: TimeInterval = 60

    private enum Weight {
        static let meetingLink = 4
        static let location = 2
        static let calendarTitle = 1
    }

    static func deduplicate(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let ordered = events.enumerated().sorted { lhs, rhs in
            lhs.element.start != rhs.element.start ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
        }
        var kept: [(offset: Int, event: CalendarEvent)] = []
        for candidate in ordered {
            let match = kept.indices.reversed()
                .prefix { candidate.element.start.timeIntervalSince(kept[$0].event.start) <= startTolerance }
                .first { isDuplicate(kept[$0].event, candidate.element) }
            guard let match else {
                kept.append((candidate.offset, candidate.element))
                continue
            }
            if prefers(candidate.element, at: candidate.offset, over: kept[match].event, at: kept[match].offset) {
                kept[match] = (candidate.offset, candidate.element)
            }
        }
        return kept.map(\.event)
    }

    static func isDuplicate(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        lhs.isAllDay == rhs.isAllDay
            && abs(lhs.start.timeIntervalSince(rhs.start)) <= startTolerance
            && normalizedTitle(lhs.title) == normalizedTitle(rhs.title)
            && linksAreCompatible(lhs.meetingLink, rhs.meetingLink)
    }

    static func richness(of event: CalendarEvent) -> Int {
        (event.meetingLink == nil ? 0 : Weight.meetingLink)
            + (event.location?.isEmpty == false ? Weight.location : 0)
            + (event.calendarTitle.isEmpty ? 0 : Weight.calendarTitle)
    }

    // MARK: - Private

    private static func prefers(_ candidate: CalendarEvent, at candidateOffset: Int, over current: CalendarEvent, at currentOffset: Int) -> Bool {
        let candidateScore = richness(of: candidate)
        let currentScore = richness(of: current)
        if candidateScore != currentScore { return candidateScore > currentScore }
        return candidateOffset < currentOffset
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.lowercased()
            .split { $0.isWhitespace }
            .joined(separator: " ")
    }

    private static func linksAreCompatible(_ lhs: MeetingLink?, _ rhs: MeetingLink?) -> Bool {
        guard let lhs, let rhs else { return true }
        return linkKey(lhs.url) == linkKey(rhs.url)
    }

    /// Host + path, ignoring scheme, query (e.g. Zoom `pwd`) and a trailing slash.
    private static func linkKey(_ url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        var path = url.path()
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }
}
