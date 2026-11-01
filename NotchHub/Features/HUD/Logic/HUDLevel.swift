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
    /// Headphones the volume plays on; `nil` for speakers and every other kind.
    let output: HUDOutputDevice?

    init(kind: HUDKind, level: Double?, isMuted: Bool = false, output: HUDOutputDevice? = nil) {
        self.kind = kind
        self.level = level.map(HUDLevel.clamped)
        self.isMuted = isMuted
        self.output = output
    }

    func with(output: HUDOutputDevice?) -> HUDReading {
        HUDReading(kind: kind, level: level, isMuted: isMuted, output: output)
    }
}

/// The end of the bar a reading sits at; drives the bounce and glow.
enum HUDLevelEdge: Equatable, Sendable {
    case empty
    case full
}

/// Pure level math and labels for the HUD.
enum HUDLevel {
    /// Volume changes smaller than this (CoreAudio float noise) do not show the HUD.
    static let changeThreshold = 0.005
    private static let dimThreshold = 0.5
    /// Absorbs float noise so a level written as 0 or 1 counts as the end of the bar.
    private static let edgeTolerance = 0.001

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

    /// Locale-aware percent ("%45" in Turkish, "45%" in English); muted volume says so.
    static func valueText(of reading: HUDReading) -> String {
        if reading.kind == .volume, reading.isMuted { return String(localized: "Sessiz") }
        guard let level = reading.level else { return title(of: reading.kind) }
        return (Double(percent(level)) / 100).formatted(.percent)
    }

    static func title(of kind: HUDKind) -> String {
        switch kind {
        case .volume: String(localized: "Ses")
        case .brightness: String(localized: "Parlaklık")
        case .keyboardBacklight: String(localized: "Klavye")
        }
    }

    static func systemImage(of reading: HUDReading) -> String {
        switch reading.kind {
        case .volume:
            if !reading.isMuted, let output = reading.output { return output.systemImage }
            return volumeImage(level: reading.level ?? 0, isMuted: reading.isMuted)
        case .brightness:
            return (reading.level ?? 1) < dimThreshold ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBacklight:
            return (reading.level ?? 1) < dimThreshold ? "light.min" : "light.max"
        }
    }

    /// Fills the speaker waves with the level; `nil` for icons without a variable value.
    static func symbolVariableValue(of reading: HUDReading) -> Double? {
        guard reading.kind == .volume, reading.output == nil, let level = displayedLevel(of: reading), level > 0 else {
            return nil
        }
        return level
    }

    /// `nil` between the ends, for unknown levels and for muted volume (which keeps its quiet look).
    static func edge(of reading: HUDReading) -> HUDLevelEdge? {
        guard !(reading.kind == .volume && reading.isMuted), let level = reading.level else { return nil }
        // Brightness bottoms out at the floor NotchHub writes, not at 0.
        let floor = reading.kind == .brightness ? MediaKeyPolicy.minimumBrightness : 0
        if level <= floor + edgeTolerance { return .empty }
        if level >= 1 - edgeTolerance { return .full }
        return nil
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

    /// One symbol for every level; `symbolVariableValue` lights its waves.
    private static func volumeImage(level: Double, isMuted: Bool) -> String {
        if isMuted || level <= 0 { return "speaker.slash.fill" }
        return "speaker.wave.3.fill"
    }
}
