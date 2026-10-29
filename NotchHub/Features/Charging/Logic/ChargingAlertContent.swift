import Foundation

/// Texts, glyph and style of the notch presentation for one `ChargingEvent`.
struct ChargingAlertContent: Equatable {
    let title: String
    let subtitle: String?
    let style: NotchAlert.Style
    let glyph: AlertBatteryGlyph
    let duration: Duration

    static let presentationDuration: Duration = .seconds(3)
    static let warningDuration: Duration = .seconds(6)
    private static let urgentThreshold = 10
    private static let separator = " · "
    private static let minutesPerHour = 60

    init(event: ChargingEvent, locale: Locale = .autoupdatingCurrent) {
        let snapshot = event.snapshot
        let percent = Self.percentText(snapshot.percent, locale: locale)
        switch event.kind {
        case .charging:
            title = snapshot.isCharging ? String(localized: "Şarj oluyor") : String(localized: "Güç adaptörüne bağlı")
            let timeText = snapshot.minutesToFull.map { Self.timeToFullText(minutes: $0) }
            subtitle = [percent, timeText].compactMap { $0 }.joined(separator: Self.separator)
            style = .success
            glyph = AlertBatteryGlyph(level: snapshot.level, state: .charging)
            duration = Self.presentationDuration
        case .unplugged:
            title = String(localized: "Pilde · \(percent)")
            subtitle = nil
            style = .info
            glyph = AlertBatteryGlyph(level: snapshot.level, state: .discharging)
            duration = Self.presentationDuration
        case .fullyCharged:
            title = String(localized: "Tamamen şarj oldu")
            subtitle = percent
            style = .success
            glyph = AlertBatteryGlyph(level: snapshot.level, state: .charging)
            duration = Self.presentationDuration
        case .lowBattery(let threshold):
            title = String(localized: "Düşük pil")
            subtitle = [String(localized: "\(percent) kaldı"), String(localized: "Güç adaptörünü bağlayın")]
                .joined(separator: Self.separator)
            style = threshold <= Self.urgentThreshold ? .urgent : .reminder
            glyph = AlertBatteryGlyph(level: snapshot.level, state: .low)
            duration = Self.warningDuration
        }
    }

    /// Locale-aware percent: "%62" in Turkish, "62%" in English.
    static func percentText(_ percent: Int, locale: Locale) -> String {
        (Double(percent) / 100).formatted(.percent.locale(locale))
    }

    /// "Dolmasına 1 sa 20 dk" / "1 h 20 min until full".
    static func timeToFullText(minutes: Int) -> String {
        String(localized: "Dolmasına \(durationText(minutes: minutes))")
    }

    /// "1 sa 20 dk", "45 dk", "2 sa" (translated through the string catalog).
    static func durationText(minutes: Int) -> String {
        let total = max(minutes, 0)
        let hours = total / minutesPerHour
        let remainder = total % minutesPerHour
        switch (hours, remainder) {
        case (0, _): return String(localized: "\(remainder) dk")
        case (_, 0): return String(localized: "\(hours) sa")
        default: return String(localized: "\(hours) sa \(remainder) dk")
        }
    }
}
