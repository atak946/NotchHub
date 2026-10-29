import Foundation

/// A system permission NotchHub can use, shown as one row in the wizard and in diagnostics.
enum AppPermission: String, CaseIterable, Identifiable, Sendable {
    case calendar
    case accessibility
    case automation
    case notifications
    case camera

    private static let privacyPane = "x-apple.systempreferences:com.apple.preference.security?"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: String(localized: "Takvim")
        case .accessibility: String(localized: "Erişilebilirlik")
        case .automation: String(localized: "Otomasyon")
        case .notifications: String(localized: "Bildirimler")
        case .camera: String(localized: "Kamera")
        }
    }

    var detail: String {
        switch self {
        case .calendar: String(localized: "Sıradaki toplantı ve hatırlatmalar")
        case .accessibility: String(localized: "Bildirim yansıtma, okunmamış sayıları, zaman takibi")
        case .automation: String(localized: "Spotify ve Music kontrolü")
        case .notifications: String(localized: "Zamanlayıcı bitince haber ver")
        case .camera: String(localized: "Toplantı öncesi ayna")
        }
    }

    var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .accessibility: "accessibility"
        case .automation: "music.note"
        case .notifications: "bell.badge"
        case .camera: "camera"
        }
    }

    /// Optional permissions only power secondary features; the wizard labels them "isteğe bağlı".
    var isOptional: Bool {
        switch self {
        case .calendar, .automation: false
        case .accessibility, .notifications, .camera: true
        }
    }

    /// Accessibility trust has no "denied" state; a refusal looks exactly like "not asked yet".
    var reportsDenialAsNotDetermined: Bool {
        self == .accessibility
    }

    /// The System Settings pane that holds this permission's switch.
    func settingsURL(bundleID: String = AppIdentity.bundleID) -> URL? {
        switch self {
        case .calendar: URL(string: Self.privacyPane + "Privacy_Calendars")
        case .accessibility: URL(string: Self.privacyPane + "Privacy_Accessibility")
        case .automation: URL(string: Self.privacyPane + "Privacy_Automation")
        case .camera: URL(string: Self.privacyPane + "Privacy_Camera")
        case .notifications: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)")
        }
    }
}

/// Live authorization state of one permission.
enum PermissionStatus: String, Sendable {
    case granted
    case notDetermined
    case denied

    var title: String {
        switch self {
        case .granted: String(localized: "İzin verildi")
        case .notDetermined: String(localized: "Sorulmadı")
        case .denied: String(localized: "Reddedildi")
        }
    }

    /// English label for the diagnostics report.
    var reportLabel: String {
        switch self {
        case .granted: "granted"
        case .notDetermined: "not determined"
        case .denied: "denied"
        }
    }
}
