import Foundation

/// Turns Dock badge text (`AXStatusLabel`) into an unread count.
enum BadgeTextParser {
    /// Upper bound so absurd labels can never overflow totals.
    static let maxCount = 99_999
    /// Non-numeric badges ("•", "!") mean "something unread" without a number.
    static let nonNumericCount = 1

    static func count(from text: String?) -> Int {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return 0
        }
        let digits = trimmed.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nonNumericCount }
        guard digits.count <= String(maxCount).count, let value = Int(digits) else { return maxCount }
        return min(value, maxCount)
    }
}
