import Foundation

/// Reads a number literal made of digits, `.` and `,`, honouring the locale's decimal separator.
///
/// Rules:
/// - both separators present: the last one is the decimal mark, the other groups thousands (`1.234,5`, `1,234.5`);
/// - the locale's decimal separator alone, once: decimal (`12,5` in Turkish);
/// - the other separator alone, once: grouping when it is followed by exactly three digits after a 1–3 digit,
///   non-zero lead (`1.500` in Turkish is 1500), otherwise decimal (`1.5`);
/// - one separator repeated: grouping, every group after the first must have three digits.
enum CalcNumberLiteral {
    private static let groupSize = 3
    private static let separators: Set<Character> = [".", ","]

    static func parse(_ raw: String, decimalSeparator: Character) -> Double? {
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && ($0.isNumber || separators.contains($0)) }) else {
            return nil
        }
        let present = Set(raw.filter { separators.contains($0) })
        guard !present.isEmpty else { return Double(raw) }
        if present.count == 2 {
            return parseMixed(raw)
        }
        guard let separator = present.first else { return nil }
        let parts = raw.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        if parts.count > 2 {
            return parseGrouped(parts)
        }
        let isGrouping = separator != decimalSeparator && looksGrouped(lead: parts[0], tail: parts[1])
        return isGrouping ? parseGrouped(parts) : decimal(integer: parts[0], fraction: parts[1])
    }

    private static func parseMixed(_ raw: String) -> Double? {
        guard let decimalIndex = raw.lastIndex(where: { separators.contains($0) }) else { return nil }
        let decimalMark = raw[decimalIndex]
        let integerPart = String(raw[..<decimalIndex])
        let fraction = String(raw[raw.index(after: decimalIndex)...])
        guard !integerPart.contains(decimalMark) else { return nil }
        let groupMark: Character = decimalMark == "." ? "," : "."
        let groups = integerPart.split(separator: groupMark, omittingEmptySubsequences: false).map(String.init)
        guard let integer = groupedDigits(groups) else { return nil }
        return decimal(integer: integer, fraction: fraction)
    }

    private static func parseGrouped(_ parts: [String]) -> Double? {
        groupedDigits(parts).flatMap { Double($0) }
    }

    private static func groupedDigits(_ groups: [String]) -> String? {
        guard let lead = groups.first, (1...groupSize).contains(lead.count) else { return nil }
        guard groups.dropFirst().allSatisfy({ $0.count == groupSize }) else { return nil }
        return groups.joined()
    }

    private static func looksGrouped(lead: String, tail: String) -> Bool {
        tail.count == groupSize && (1...groupSize).contains(lead.count) && lead != "0"
    }

    private static func decimal(integer: String, fraction: String) -> Double? {
        guard !(integer.isEmpty && fraction.isEmpty) else { return nil }
        let normalized = (integer.isEmpty ? "0" : integer) + "." + (fraction.isEmpty ? "0" : fraction)
        return Double(normalized)
    }
}
