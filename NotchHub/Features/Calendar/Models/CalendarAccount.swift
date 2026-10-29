import EventKit
import Foundation

/// The kind of account a calendar lives in, as configured in macOS Internet Accounts.
enum CalendarAccountKind: String, CaseIterable, Hashable, Sendable {
    case outlook
    case google
    case iCloud
    case local
    case subscribed
    case other

    var displayName: String {
        switch self {
        case .outlook: "Outlook"
        case .google: "Google"
        case .iCloud: "iCloud"
        case .local: String(localized: "Bu Mac'te")
        case .subscribed: String(localized: "Abone olunan")
        case .other: String(localized: "Diğer")
        }
    }

    var systemImage: String {
        switch self {
        case .outlook: "envelope.fill"
        case .google: "globe"
        case .iCloud: "icloud.fill"
        case .local: "desktopcomputer"
        case .subscribed: "dot.radiowaves.up.forward"
        case .other: "calendar"
        }
    }

    /// Display order when listing accounts.
    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    private static let outlookMarkers = ["outlook", "office365", "office 365", "hotmail", "live.com", "msn.com"]
    private static let outlookWords: Set<String> = ["live", "exchange", "microsoft"]
    private static let googleMarkers = ["gmail", "google"]
    private static let iCloudMarkers = ["icloud"]

    /// Pure mapping from an EventKit source to an account kind.
    static func classify(sourceType: EKSourceType, title: String) -> CalendarAccountKind {
        switch sourceType {
        case .exchange:
            return .outlook
        case .mobileMe:
            return .iCloud
        case .local:
            return .local
        case .subscribed, .birthdays:
            return .subscribed
        case .calDAV:
            return classifyCalDAV(title: title)
        @unknown default:
            return .other
        }
    }

    private static func classifyCalDAV(title: String) -> CalendarAccountKind {
        let lowered = title.lowercased()
        let words = Set(lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if outlookMarkers.contains(where: lowered.contains) || !words.isDisjoint(with: outlookWords) {
            return .outlook
        }
        if googleMarkers.contains(where: lowered.contains) {
            return .google
        }
        if iCloudMarkers.contains(where: lowered.contains) {
            return .iCloud
        }
        return .other
    }
}

/// An account (EventKit source) that owns one or more calendars.
struct CalendarAccount: Hashable, Identifiable, Sendable {
    static let unknown = CalendarAccount(id: "unknown", title: String(localized: "Diğer"), kind: .other)

    /// `EKSource.sourceIdentifier`.
    let id: String
    let title: String
    let kind: CalendarAccountKind

    /// Title shown in the UI: the account title, or the kind name when the title is empty.
    var displayTitle: String {
        title.isEmpty ? kind.displayName : title
    }
}
