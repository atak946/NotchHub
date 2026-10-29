import Foundation

/// RFC 4180 CSV of ledger entries: `Date,Client,App,Minutes`, CRLF line endings.
enum TimeCSVExporter {
    static var header: [String] {
        [String(localized: "Tarih"), String(localized: "Müşteri"), String(localized: "Uygulama"), String(localized: "Dakika")]
    }
    static let lineEnding = "\r\n"
    private static let secondsPerMinute = 60.0
    private static let charactersNeedingQuotes: Set<Character> = [",", "\"", "\n", "\r"]
    /// Leading characters spreadsheets would evaluate as a formula (CSV injection).
    private static let formulaPrefixes: Set<Character> = ["=", "+", "-", "@", "\t"]

    static func csv(for entries: [TimeLedgerEntry]) -> String {
        let rows = entries
            .sorted { ($0.day, $0.client, $0.appBundleID) < ($1.day, $1.client, $1.appBundleID) }
            .map { [$0.day, $0.client, $0.appBundleID, minutes($0.seconds)] }
        return ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: lineEnding) + lineEnding
    }

    static func escape(_ field: String) -> String {
        let neutralized = field.first.map(formulaPrefixes.contains) == true ? "'" + field : field
        guard neutralized.contains(where: charactersNeedingQuotes.contains) else { return neutralized }
        return "\"" + neutralized.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// One decimal, always "." as separator.
    static func minutes(_ seconds: Int) -> String {
        String(format: "%.1f", Double(seconds) / secondsPerMinute)
    }
}
