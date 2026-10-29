import Foundation

enum MeetingProvider: String, CaseIterable, Hashable, Sendable {
    case zoom
    case teams
    case meet
    case webex
    case other

    var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .teams: "Teams"
        case .meet: "Meet"
        case .webex: "Webex"
        case .other: "Toplantı"
        }
    }

    var systemImage: String {
        switch self {
        case .zoom: "video.fill"
        case .teams: "person.3.fill"
        case .meet: "video.circle.fill"
        case .webex: "video.square.fill"
        case .other: "link"
        }
    }

    /// Brand-like tint used for the Join button (sRGB).
    var tint: CalendarColor {
        switch self {
        case .zoom: CalendarColor(red: 0.16, green: 0.45, blue: 0.98)
        case .teams: CalendarColor(red: 0.38, green: 0.39, blue: 0.78)
        case .meet: CalendarColor(red: 0.0, green: 0.6, blue: 0.42)
        case .webex: CalendarColor(red: 0.0, green: 0.62, blue: 0.62)
        case .other: CalendarColor(red: 0.35, green: 0.45, blue: 0.95)
        }
    }
}

struct MeetingLink: Equatable, Sendable {
    let provider: MeetingProvider
    let url: URL
}
