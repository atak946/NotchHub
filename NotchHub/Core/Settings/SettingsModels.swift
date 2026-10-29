enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case builtIn
    case main
    case allScreens
    case followMouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: "Yerleşik ekran"
        case .main: "Ana ekran"
        case .allScreens: "Tüm ekranlar"
        case .followMouse: "Fare olan ekran"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Sistem"
        case .dark: "Koyu"
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
        case .shelf: "Dosya Rafı"
        case .media: "Şimdi Çalıyor"
        case .timer: "Zamanlayıcı"
        case .calendar: "Sıradaki Toplantı"
        case .notes: "Notlar"
        case .status: "Durum"
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
