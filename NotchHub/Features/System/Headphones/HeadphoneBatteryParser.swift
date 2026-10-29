import Foundation

/// Pure parser for `system_profiler SPBluetoothDataType -json`.
enum HeadphoneBatteryParser {
    private static let rootKey = "SPBluetoothDataType"
    private static let connectedKey = "device_connected"
    private static let leftKey = "device_batteryLevelLeft"
    private static let rightKey = "device_batteryLevelRight"
    private static let caseKey = "device_batteryLevelCase"
    private static let mainKey = "device_batteryLevelMain"
    private static let maxPercent = 100

    /// Battery levels of the connected device named `deviceName`; nil when it is missing or reports none.
    static func parseSystemProfiler(_ data: Data, deviceName: String) -> HeadphoneBatteryLevels? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root[rootKey] as? [[String: Any]] else { return nil }
        for controller in controllers {
            guard let connected = controller[connectedKey] as? [[String: Any]] else { continue }
            if let levels = levels(in: connected, deviceName: deviceName) { return levels }
        }
        return nil
    }

    /// "80%", "%80", "80 %" or a number → 80; nil outside 0...100.
    static func percent(from value: Any?) -> Int? {
        let number: Int?
        switch value {
        case let int as Int:
            number = int
        case let string as String:
            let digits = string.filter(\.isASCII).filter(\.isNumber)
            number = digits.isEmpty ? nil : Int(digits)
        default:
            number = nil
        }
        guard let number, (0...maxPercent).contains(number) else { return nil }
        return number
    }

    /// CoreAudio and Bluetooth names can differ in case, spacing and apostrophe style.
    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    // MARK: - Private

    private static func levels(in devices: [[String: Any]], deviceName: String) -> HeadphoneBatteryLevels? {
        for entry in devices {
            for (name, value) in entry where namesMatch(name, deviceName) {
                guard let properties = value as? [String: Any] else { continue }
                let levels = HeadphoneBatteryLevels(
                    left: percent(from: properties[leftKey]),
                    right: percent(from: properties[rightKey]),
                    caseLevel: percent(from: properties[caseKey]),
                    main: percent(from: properties[mainKey])
                )
                return levels.isEmpty ? nil : levels
            }
        }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
