enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case builtIn
    case main
    case allScreens
    case followMouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: String(localized: "Yerleşik ekran")
        case .main: String(localized: "Ana ekran")
        case .allScreens: String(localized: "Tüm ekranlar")
        case .followMouse: String(localized: "Fare olan ekran")
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .dark: String(localized: "Koyu")
        }
    }
}

enum NotchModule: String, CaseIterable, Identifiable, Sendable {
    case shelf
    case media
    case timer
    case calendar
    case notes
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf: String(localized: "Dosya Rafı")
        case .media: String(localized: "Şimdi Çalıyor")
        case .timer: String(localized: "Zamanlayıcı")
        case .calendar: String(localized: "Sıradaki Toplantı")
        case .notes: String(localized: "Notlar")
        case .status: String(localized: "Durum")
        }
    }

    var systemImage: String {
        switch self {
        case .shelf: "tray.full"
        case .media: "music.note"
        case .timer: "timer"
        case .calendar: "calendar"
        case .notes: "note.text"
        case .status: "gauge.with.dots.needle.67percent"
        }
    }
}
