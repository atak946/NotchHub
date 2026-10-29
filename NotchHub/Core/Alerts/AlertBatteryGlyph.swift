import Foundation

/// Battery level visual that replaces the leading icon of a power alert (charging, unplugged, low).
struct AlertBatteryGlyph: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case charging
        case discharging
        case low
    }

    private static let quarter = 0.25
    private static let half = 0.5
    private static let threeQuarters = 0.75
    private static let nearlyFull = 0.95

    /// 0…1.
    let level: Double
    let state: State

    init(level: Double, state: State) {
        self.level = level.isNaN ? 0 : min(max(level, 0), 1)
        self.state = state
    }

    /// Centre symbol: a bolt while charging, otherwise a battery matching the level.
    var systemImage: String {
        if state == .charging { return "bolt.fill" }
        if level >= Self.nearlyFull { return "battery.100percent" }
        if level >= Self.threeQuarters { return "battery.75percent" }
        if level >= Self.half { return "battery.50percent" }
        if level >= Self.quarter { return "battery.25percent" }
        return "battery.0percent"
    }
}
