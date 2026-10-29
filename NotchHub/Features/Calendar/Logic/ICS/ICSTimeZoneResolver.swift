import Foundation

/// Resolves a TZID (IANA, Windows name, `(UTC+03:00) …` label or a VTIMEZONE-defined custom id) to a `TimeZone`.
enum ICSTimeZoneResolver {
    private static let microsoftPrefix = "tzone://microsoft/"
    private static let microsoftUTC = "utc"
    private static let utcLabelPrefixes = ["(utc", "(gmt", "utc", "gmt"]
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    /// - Parameter customOffsets: TZID → standard UTC offset (seconds) taken from the file's VTIMEZONE blocks.
    static func timeZone(for rawTZID: String, customOffsets: [String: Int] = [:]) -> TimeZone? {
        let tzid = rawTZID.trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespaces))
        guard !tzid.isEmpty else { return nil }

        if tzid.lowercased().hasPrefix(microsoftPrefix) {
            let rest = tzid.dropFirst(microsoftPrefix.count).lowercased()
            if rest == microsoftUTC { return TimeZone(identifier: "UTC") }
        }
        if let iana = WindowsTimeZoneMap.ianaIdentifier(forWindowsName: tzid), let zone = TimeZone(identifier: iana) {
            return zone
        }
        if let zone = ianaZone(tzid) {
            return zone
        }
        if let offset = customOffsets[tzid], let zone = TimeZone(secondsFromGMT: offset) {
            return zone
        }
        if let offset = utcOffset(inLabel: tzid), let zone = TimeZone(secondsFromGMT: offset) {
            return zone
        }
        return nil
    }

    /// Parses `+0300`, `-0530`, `+03:00` as used by TZOFFSETTO.
    static func offsetSeconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let sign = trimmed.first, sign == "+" || sign == "-" else { return nil }
        let digits = trimmed.dropFirst().filter(\.isNumber)
        guard digits.count >= 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.dropFirst(2).prefix(2)) else {
            return nil
        }
        let seconds = hours * secondsPerHour + minutes * secondsPerMinute
        return sign == "-" ? -seconds : seconds
    }

    // MARK: - Private

    private static func ianaZone(_ tzid: String) -> TimeZone? {
        // Only accept region-style identifiers so abbreviations like "EST" do not resolve to surprising zones.
        if tzid.contains("/"), let zone = TimeZone(identifier: tzid) {
            return zone
        }
        if ["UTC", "GMT", "Z"].contains(tzid.uppercased()) {
            return TimeZone(identifier: "UTC")
        }
        // "/mozilla.org/20050126_1/Europe/Berlin" style: try trailing path components.
        let components = tzid.split(separator: "/").map(String.init)
        guard components.count > 2 else { return nil }
        for count in [3, 2] where components.count >= count {
            let candidate = components.suffix(count).joined(separator: "/")
            if let zone = TimeZone(identifier: candidate) { return zone }
        }
        return nil
    }

    /// "(UTC+03:00) Istanbul" → 10800.
    private static func utcOffset(inLabel label: String) -> Int? {
        let lowered = label.lowercased()
        guard let prefix = utcLabelPrefixes.first(where: lowered.hasPrefix) else { return nil }
        let rest = lowered.dropFirst(prefix.count)
        if rest.hasPrefix(")") { return 0 }
        let offsetText = rest.prefix { $0 == "+" || $0 == "-" || $0.isNumber || $0 == ":" }
        return offsetSeconds(String(offsetText))
    }
}
