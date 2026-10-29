import Foundation

/// Which system level the HUD shows.
enum HUDKind: Equatable, Sendable {
    case volume
    case brightness
    case keyboardBacklight
}

/// One level snapshot for the HUD. `level` is 0…1, or `nil` when it cannot be read.
struct HUDReading: Equatable, Sendable {
    let kind: HUDKind
    let level: Double?
    let isMuted: Bool

    init(kind: HUDKind, level: Double?, isMuted: Bool = false) {
        self.kind = kind
        self.level = level.map(HUDLevel.clamped)
        self.isMuted = isMuted
    }
}

/// Pure level math and labels for the HUD.
enum HUDLevel {
    /// Volume changes smaller than this (CoreAudio float noise) do not show the HUD.
    static let changeThreshold = 0.005
    private static let lowThreshold = 1.0 / 3
    private static let highThreshold = 2.0 / 3
    private static let dimThreshold = 0.5

    /// Clamps to 0…1; NaN becomes 0.
    static func clamped(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(max(value, 0), 1)
    }

    static func percent(_ level: Double) -> Int {
        Int((clamped(level) * 100).rounded())
    }

    /// The bar fill: muted volume reads as empty, unknown levels have no bar.
    static func displayedLevel(of reading: HUDReading) -> Double? {
        if reading.kind == .volume, reading.isMuted { return 0 }
        return reading.level
    }

    /// Turkish puts the percent sign first ("%45"); muted volume says so.
    static func valueText(of reading: HUDReading) -> String {
        if reading.kind == .volume, reading.isMuted { return "Sessiz" }
        guard let level = reading.level else { return title(of: reading.kind) }
        return "%\(percent(level))"
    }

    static func title(of kind: HUDKind) -> String {
        switch kind {
        case .volume: "Ses"
        case .brightness: "Parlaklık"
        case .keyboardBacklight: "Klavye"
        }
    }

    static func systemImage(of reading: HUDReading) -> String {
        switch reading.kind {
        case .volume:
            return volumeImage(level: reading.level ?? 0, isMuted: reading.isMuted)
        case .brightness:
            return (reading.level ?? 1) < dimThreshold ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBacklight:
            return (reading.level ?? 1) < dimThreshold ? "light.min" : "light.max"
        }
    }

    /// Whether a new volume reading differs enough from the last one to show the HUD.
    /// The first reading (no previous value) only sets the baseline.
    static func isMeaningfulChange(from previous: HUDReading?, to next: HUDReading) -> Bool {
        guard let previous else { return false }
        if previous.isMuted != next.isMuted { return true }
        switch (previous.level, next.level) {
        case let (old?, new?):
            return abs(old - new) >= changeThreshold
        case (nil, nil):
            return false
        default:
            return true
        }
    }

    private static func volumeImage(level: Double, isMuted: Bool) -> String {
        if isMuted || level <= 0 { return "speaker.slash.fill" }
        if level < lowThreshold { return "speaker.wave.1.fill" }
        if level < highThreshold { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
