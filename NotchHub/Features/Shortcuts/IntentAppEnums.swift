import AppIntents

/// Panel modules selectable from Shortcuts.
enum IntentModule: String, AppEnum {
    case shelf
    case media
    case timer
    case calendar
    case notes
    case status

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modül"

    static let caseDisplayRepresentations: [IntentModule: DisplayRepresentation] = [
        .shelf: DisplayRepresentation(title: "Dosya Rafı", image: .init(systemName: "tray.full")),
        .media: DisplayRepresentation(title: "Şimdi Çalıyor", image: .init(systemName: "music.note")),
        .timer: DisplayRepresentation(title: "Zamanlayıcı", image: .init(systemName: "timer")),
        .calendar: DisplayRepresentation(title: "Sıradaki Toplantı", image: .init(systemName: "calendar")),
        .notes: DisplayRepresentation(title: "Notlar", image: .init(systemName: "note.text")),
        .status: DisplayRepresentation(title: "Durum", image: .init(systemName: "gauge.with.dots.needle.67percent")),
    ]

    var notchModule: NotchModule {
        switch self {
        case .shelf: .shelf
        case .media: .media
        case .timer: .timer
        case .calendar: .calendar
        case .notes: .notes
        case .status: .status
        }
    }
}

/// Alert styles selectable from Shortcuts.
enum IntentAlertStyle: String, AppEnum {
    case info
    case success
    case reminder
    case urgent

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Uyarı Türü"

    static let caseDisplayRepresentations: [IntentAlertStyle: DisplayRepresentation] = [
        .info: "Bilgi",
        .success: "Başarılı",
        .reminder: "Hatırlatma",
        .urgent: "Acil",
    ]

    var notchStyle: NotchAlert.Style {
        switch self {
        case .info: .info
        case .success: .success
        case .reminder: .reminder
        case .urgent: .urgent
        }
    }
}
