import Foundation

/// How long an item stays on the shelf before it is removed automatically.
enum ShelfRetention: String, CaseIterable, Identifiable, Sendable {
    case off
    case oneHour
    case oneDay
    case sevenDays

    private static let secondsPerHour: TimeInterval = 3_600
    private static let hoursPerDay: TimeInterval = 24
    private static let daysPerWeek: TimeInterval = 7

    var id: String { rawValue }

    /// `nil` means items are kept until removed manually.
    var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .oneHour: Self.secondsPerHour
        case .oneDay: Self.secondsPerHour * Self.hoursPerDay
        case .sevenDays: Self.secondsPerHour * Self.hoursPerDay * Self.daysPerWeek
        }
    }

    var title: String {
        switch self {
        case .off: String(localized: "Asla")
        case .oneHour: String(localized: "1 saat sonra")
        case .oneDay: String(localized: "1 gün sonra")
        case .sevenDays: String(localized: "7 gün sonra")
        }
    }
}
