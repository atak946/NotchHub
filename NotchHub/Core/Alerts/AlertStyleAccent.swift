import SwiftUI

/// Accent colours tuned for the black notch: bright enough to read, never neon.
extension NotchAlert.Style {
    var tint: Color {
        switch self {
        case .info: Color(red: 0.40, green: 0.66, blue: 1.0)
        case .reminder: Color(red: 1.0, green: 0.72, blue: 0.30)
        case .success: Color(red: 0.34, green: 0.86, blue: 0.56)
        case .urgent: Color(red: 1.0, green: 0.40, blue: 0.38)
        }
    }

    /// Peak opacity of the soft glow under the notch.
    var glowOpacity: Double {
        switch self {
        case .info: 0.22
        case .reminder: 0.28
        case .success: 0.24
        case .urgent: 0.42
        }
    }

    /// Only urgent alerts breathe; the others keep a steady glow.
    var glowPulses: Bool { self == .urgent }

    var accessibilityName: String {
        switch self {
        case .info: String(localized: "Bilgi")
        case .reminder: String(localized: "Hatırlatma")
        case .success: String(localized: "Tamamlandı")
        case .urgent: String(localized: "Acil")
        }
    }
}
