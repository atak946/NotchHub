import CoreGraphics

/// A media command reachable from the collapsed notch, in left-to-right order.
enum MediaControlAction: Int, CaseIterable, Identifiable, Sendable {
    case previous
    case playPause
    case next

    var id: Int { rawValue }

    func systemImage(isPlaying: Bool) -> String {
        switch self {
        case .previous: "backward.fill"
        case .playPause: isPlaying ? "pause.fill" : "play.fill"
        case .next: "forward.fill"
        }
    }

    func title(isPlaying: Bool) -> String {
        switch self {
        case .previous: String(localized: "Önceki parça")
        case .playPause: isPlaying ? String(localized: "Duraklat") : String(localized: "Oynat")
        case .next: String(localized: "Sonraki parça")
        }
    }
}

/// What a click on the collapsed notch should do.
enum CompactClickRoute: Equatable, Sendable {
    case mediaControl(MediaControlAction)
    case openPanel
    case passThrough
}

/// Pure visibility rules for the collapsed media controls.
enum CompactMediaControls {
    /// Whether the controls are part of the collapsed layout (wing width and rendering).
    static func isAvailable(isEnabled: Bool, hasActiveTrack: Bool) -> Bool {
        isEnabled && hasActiveTrack
    }

    /// Whether the controls take clicks and block hover-to-open right now.
    static func isInteractive(isAvailable: Bool, isAlertShowing: Bool, isExpanded: Bool) -> Bool {
        isAvailable && !isAlertShowing && !isExpanded
    }
}
