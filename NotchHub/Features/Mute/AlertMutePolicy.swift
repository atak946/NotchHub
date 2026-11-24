import Foundation

/// Manual mute lengths offered in the menu and in Settings.
enum AlertMuteDuration: CaseIterable, Identifiable, Sendable {
    case oneHour
    case untilTomorrow
    case untilTurnedOff

    private static let hour: TimeInterval = 3600

    var id: Self { self }

    var title: String {
        switch self {
        case .oneHour: String(localized: "1 saat")
        case .untilTomorrow: String(localized: "Yarına kadar")
        case .untilTurnedOff: String(localized: "Ben açana kadar")
        }
    }

    func end(from date: Date, calendar: Calendar) -> Date {
        switch self {
        case .oneHour:
            date.addingTimeInterval(Self.hour)
        case .untilTomorrow:
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(24 * Self.hour)
        case .untilTurnedOff:
            .distantFuture
        }
    }
}

/// Why notifications are muted right now.
enum AlertMuteReason: Equatable, Sendable {
    /// `.distantFuture` stays muted until the user turns it off.
    case manual(until: Date)
    case meeting
    case focus

    var title: String {
        switch self {
        case .manual(.distantFuture): String(localized: "Bildirimler susturuldu")
        case .manual(let until): String(localized: "\(until.formatted(date: .omitted, time: .shortened)) saatine kadar susturuldu")
        case .meeting: String(localized: "Toplantı sırasında susturuldu")
        case .focus: String(localized: "Odak sırasında susturuldu")
        }
    }
}

enum AlertMutePolicy {
    static func reason(
        manualUntil: Date?,
        now: Date,
        isInMeeting: Bool,
        isInFocus: Bool,
        overridesAutomatic: Bool
    ) -> AlertMuteReason? {
        if let manualUntil, manualUntil > now { return .manual(until: manualUntil) }
        guard !overridesAutomatic else { return nil }
        if isInMeeting { return .meeting }
        return isInFocus ? .focus : nil
    }

    static func shouldPresent(_ behavior: AlertMuteBehavior, isMuted: Bool, allowsTimeSensitive: Bool) -> Bool {
        guard isMuted else { return true }
        return switch behavior {
        case .always: true
        case .timeSensitive: allowsTimeSensitive
        case .drop, .hold: false
        }
    }

    static func isHeld(_ behavior: AlertMuteBehavior) -> Bool {
        behavior == .hold || behavior == .timeSensitive
    }

    /// "WhatsApp 3 · Outlook 2", most frequent source first.
    static func summary(of sources: [String], maxSources: Int) -> String {
        let counts: [String: Int] = sources.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        let ordered = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        return ordered.prefix(maxSources).map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }
}
