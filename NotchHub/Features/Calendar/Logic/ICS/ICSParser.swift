import Foundation

/// Robust, dependency-free iCalendar (RFC 5545) reader for VEVENTs as published by Outlook / Exchange,
/// Google and most other servers. Unknown properties and components are ignored.
enum ICSParser {
    private enum Component {
        static let calendar = "VCALENDAR"
        static let event = "VEVENT"
        static let timeZone = "VTIMEZONE"
        static let standard = "STANDARD"
        static let daylight = "DAYLIGHT"
    }

    private static let cancelledStatus = "CANCELLED"

    static func parse(_ text: String) -> ICSCalendarData {
        let lines = ICSContentLineReader.lines(in: text)
        let offsets = customTimeZoneOffsets(in: lines)
        var data = ICSCalendarData()
        var stack: [String] = []
        var eventLines: [ICSContentLine]?

        for line in lines {
            switch line.name {
            case "BEGIN":
                let component = line.value.uppercased()
                stack.append(component)
                if component == Component.event { eventLines = [] }
            case "END":
                let component = line.value.uppercased()
                if component == Component.event, let collected = eventLines {
                    if let event = event(from: collected, offsets: offsets) { data.events.append(event) }
                    eventLines = nil
                }
                if let index = stack.lastIndex(of: component) { stack.removeSubrange(index...) }
            default:
                if stack.last == Component.event {
                    eventLines?.append(line)
                } else if stack.last == Component.calendar, line.name == "X-WR-CALNAME" {
                    data.name = ICSContentLineReader.unescapeText(line.value)
                }
            }
        }
        return data
    }

    // MARK: - VEVENT

    private static func event(from lines: [ICSContentLine], offsets: [String: Int]) -> ICSRawEvent? {
        var event = ICSRawEvent()
        var rawRule: String?
        for line in lines {
            apply(line, to: &event, rawRule: &rawRule, offsets: offsets)
        }
        guard let start = event.start else { return nil }
        if let rawRule {
            let tzid = lines.first { $0.name == "DTSTART" }?.parameter("TZID")
            event.rule = ICSValueParser.recurrenceRule(rawRule, tzid: tzid, customOffsets: offsets)
        }
        if event.uid.isEmpty {
            event.uid = "\(event.summary ?? "event")-\(Int(start.date.timeIntervalSince1970))"
        }
        return event
    }

    private static func apply(
        _ line: ICSContentLine,
        to event: inout ICSRawEvent,
        rawRule: inout String?,
        offsets: [String: Int]
    ) {
        let text = { nonEmpty(ICSContentLineReader.unescapeText(line.value)) }
        let date = { ICSValueParser.dateTime(line.value, tzid: line.parameter("TZID"), customOffsets: offsets) }
        switch line.name {
        case "UID": event.uid = line.value.trimmingCharacters(in: .whitespaces)
        case "SUMMARY": event.summary = text()
        case "DTSTART": event.start = date()
        case "DTEND": event.end = date()
        case "DURATION": event.duration = ICSValueParser.duration(line.value)
        case "RRULE": rawRule = line.value
        case "EXDATE":
            let dates = ICSValueParser.dateTimes(line.value, tzid: line.parameter("TZID"), customOffsets: offsets)
            event.exceptionDates.append(contentsOf: dates.map(\.date))
        case "RECURRENCE-ID": event.recurrenceID = date()?.date
        case "STATUS": event.isCancelled = line.value.trimmingCharacters(in: .whitespaces).uppercased() == cancelledStatus
        case "LOCATION": event.location = text()
        case "DESCRIPTION": event.description = text()
        case "URL": event.url = nonEmpty(line.value)
        case "X-MICROSOFT-SKYPETEAMSMEETINGURL": event.teamsMeetingURL = nonEmpty(line.value)
        case "X-MICROSOFT-ONLINEMEETINGCONFLINK": event.conferenceLink = nonEmpty(line.value)
        default: break
        }
    }

    // MARK: - VTIMEZONE

    /// TZID → standard offset of custom VTIMEZONE definitions (used only when the TZID is not a known zone).
    private static func customTimeZoneOffsets(in lines: [ICSContentLine]) -> [String: Int] {
        var offsets: [String: Int] = [:]
        var daylightFallback: [String: Int] = [:]
        var currentTZID: String?
        var subComponent: String?
        for line in lines {
            switch (line.name, line.value.uppercased()) {
            case ("BEGIN", Component.timeZone):
                currentTZID = nil
            case ("END", Component.timeZone):
                currentTZID = nil
                subComponent = nil
            case ("BEGIN", Component.standard), ("BEGIN", Component.daylight):
                subComponent = line.value.uppercased()
            case ("END", Component.standard), ("END", Component.daylight):
                subComponent = nil
            case ("TZID", _):
                currentTZID = line.value.trimmingCharacters(in: .whitespaces)
            case ("TZOFFSETTO", _):
                guard let tzid = currentTZID, let offset = ICSTimeZoneResolver.offsetSeconds(line.value) else { continue }
                if subComponent == Component.standard, offsets[tzid] == nil {
                    offsets[tzid] = offset
                } else if subComponent == Component.daylight, daylightFallback[tzid] == nil {
                    daylightFallback[tzid] = offset
                }
            default:
                continue
            }
        }
        return daylightFallback.merging(offsets) { _, standard in standard }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
