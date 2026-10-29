import Foundation

/// Sidebar groups of the Settings window, in display order.
enum SettingsCategoryGroup: String, CaseIterable, Identifiable, Sendable {
    case notchHub
    case modules
    case communication
    case system
    case developer

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .notchHub: "NotchHub"
        case .modules: "Modüller"
        case .communication: "İletişim"
        case .system: "Sistem"
        case .developer: "Geliştirici"
        }
    }

    var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0.group == self }
    }
}

/// One page of the Settings window. The raw value is persisted, so do not rename cases.
enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general
    case notch
    case hud
    case alerts
    case shelf
    case media
    case timer
    case calendar
    case notes
    case weather
    case battery
    case notifications
    case unread
    case meeting
    case network
    case headphones
    case performance
    case remoteSession
    case devOps
    case profiles
    case integrations
    case shortcuts
    case automations
    case timeTracking

    /// `UserDefaults` key of the selected page, shared by the window and code that opens a specific page.
    static let storageKey = "settings.selectedCategory"
    static let defaultCategory: SettingsCategory = .general

    var id: String { rawValue }

    var group: SettingsCategoryGroup {
        switch self {
        case .general, .notch, .hud, .alerts: .notchHub
        case .shelf, .media, .timer, .calendar, .notes, .weather, .battery: .modules
        case .notifications, .unread, .meeting: .communication
        case .network, .headphones, .performance, .remoteSession: .system
        case .devOps, .profiles, .integrations, .shortcuts, .automations, .timeTracking: .developer
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .general: "Genel"
        case .notch: "Çentik ve Görünüm"
        case .hud: "Sistem HUD'u"
        case .alerts: "Uyarılar"
        case .shelf: "Raf ve Pano"
        case .media: "Medya"
        case .timer: "Zamanlayıcı"
        case .calendar: "Takvim"
        case .notes: "Notlar ve Hesap"
        case .weather: "Hava Durumu"
        case .battery: "Pil"
        case .notifications: "Bildirimler"
        case .unread: "Okunmamış Mesajlar"
        case .meeting: "Toplantı"
        case .network: "Ağ ve VPN"
        case .headphones: "Kulaklık"
        case .performance: "Performans"
        case .remoteSession: "Uzak Oturum"
        case .devOps: "DevOps"
        case .profiles: "Profiller"
        case .integrations: "Entegrasyonlar"
        case .shortcuts: "Kestirmeler"
        case .automations: "Otomasyonlar"
        case .timeTracking: "Zaman Takibi"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .notch: "macbook"
        case .hud: "speaker.wave.2.fill"
        case .alerts: "bell.badge.fill"
        case .shelf: "tray.full.fill"
        case .media: "music.note"
        case .timer: "timer"
        case .calendar: "calendar"
        case .notes: "note.text"
        case .weather: "cloud.sun.fill"
        case .battery: "battery.100percent.bolt"
        case .notifications: "app.badge.fill"
        case .unread: "envelope.badge.fill"
        case .meeting: "video.fill"
        case .network: "network"
        case .headphones: "airpodspro"
        case .performance: "gauge.with.dots.needle.67percent"
        case .remoteSession: "display.2"
        case .devOps: "shippingbox.fill"
        case .profiles: "person.crop.rectangle.stack.fill"
        case .integrations: "puzzlepiece.extension.fill"
        case .shortcuts: "command"
        case .automations: "wand.and.stars"
        case .timeTracking: "clock.fill"
        }
    }

    /// Restores a persisted value, falling back to the default page for unknown or missing values.
    static func restored(from rawValue: String?) -> SettingsCategory {
        rawValue.flatMap(SettingsCategory.init(rawValue:)) ?? defaultCategory
    }

    /// Makes `category` the page shown the next time (or right now, if open) the Settings window appears.
    static func select(_ category: SettingsCategory, in defaults: UserDefaults = .standard) {
        defaults.set(category.rawValue, forKey: storageKey)
    }
}
