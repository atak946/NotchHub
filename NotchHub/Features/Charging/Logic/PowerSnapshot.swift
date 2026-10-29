import Foundation

/// One reading of the internal battery. Machines without a battery have no snapshot at all.
struct PowerSnapshot: Equatable, Sendable {
    static let fullPercent = 100

    /// 0…100.
    let percent: Int
    /// On external (AC) power.
    let isPluggedIn: Bool
    let isCharging: Bool
    /// IOKit's "Is Charged" flag: plugged in and no longer charging because the battery is full.
    let isCharged: Bool
    /// `nil` while IOKit is still calculating or when not charging.
    let minutesToFull: Int?

    init(percent: Int, isPluggedIn: Bool, isCharging: Bool, isCharged: Bool = false, minutesToFull: Int? = nil) {
        self.percent = min(max(percent, 0), Self.fullPercent)
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.minutesToFull = minutesToFull.flatMap { $0 > 0 ? $0 : nil }
    }

    var isFull: Bool {
        isCharged || percent >= Self.fullPercent
    }

    /// 0…1 for glyphs.
    var level: Double {
        Double(percent) / Double(Self.fullPercent)
    }
}

/// Turns one IOKit power source description (`IOPSGetPowerSourceDescription`) into a snapshot.
enum PowerSnapshotParser {
    enum Key {
        static let type = "Type"
        static let isPresent = "Is Present"
        static let currentCapacity = "Current Capacity"
        static let maxCapacity = "Max Capacity"
        static let powerSourceState = "Power Source State"
        static let isCharging = "Is Charging"
        static let isCharged = "Is Charged"
        static let timeToFull = "Time to Full Charge"
    }

    static let internalBatteryType = "InternalBattery"
    static let acPowerValue = "AC Power"

    /// `nil` for anything but a present internal battery with a usable capacity.
    static func snapshot(from description: [String: Any]) -> PowerSnapshot? {
        guard description[Key.type] as? String == internalBatteryType else { return nil }
        if let isPresent = description[Key.isPresent] as? Bool, !isPresent { return nil }
        guard let current = description[Key.currentCapacity] as? Int,
              let maximum = description[Key.maxCapacity] as? Int,
              maximum > 0
        else { return nil }
        let percent = Int((Double(current) / Double(maximum) * 100).rounded())
        let isPluggedIn = description[Key.powerSourceState] as? String == acPowerValue
        let isCharging = description[Key.isCharging] as? Bool ?? false
        let isCharged = description[Key.isCharged] as? Bool ?? false
        let minutes = isCharging ? description[Key.timeToFull] as? Int : nil
        return PowerSnapshot(
            percent: percent,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            isCharged: isCharged,
            minutesToFull: minutes
        )
    }
}
