import Foundation

/// Battery percentages (0...100) of a Bluetooth audio device; AirPods report left / right / case.
struct HeadphoneBatteryLevels: Equatable, Sendable {
    let left: Int?
    let right: Int?
    let caseLevel: Int?
    /// Single-battery headsets.
    let main: Int?

    var isEmpty: Bool {
        left == nil && right == nil && caseLevel == nil && main == nil
    }
}

/// The last successful battery read, shown on the status tile.
struct HeadphoneBatteryReport: Equatable, Sendable {
    let deviceName: String
    let levels: HeadphoneBatteryLevels
    let readAt: Date
}

/// A Bluetooth output device as seen by CoreAudio.
struct BluetoothAudioOutput: Equatable, Sendable {
    let id: UInt32
    let name: String
}

/// Connected Bluetooth outputs plus the current default output.
struct BluetoothAudioSnapshot: Equatable, Sendable {
    static let empty = BluetoothAudioSnapshot(outputs: [], defaultOutputID: nil)

    let outputs: [BluetoothAudioOutput]
    let defaultOutputID: UInt32?

    var defaultBluetoothOutput: BluetoothAudioOutput? {
        guard let defaultOutputID else { return nil }
        return outputs.first { $0.id == defaultOutputID }
    }

    func contains(name: String) -> Bool {
        outputs.contains { $0.name == name }
    }
}

/// Which device (if any) a snapshot change should report on. Disconnects never report.
enum HeadphoneConnectPolicy {
    static func connectedDevice(previous: BluetoothAudioSnapshot, current: BluetoothAudioSnapshot) -> BluetoothAudioOutput? {
        let previousIDs = Set(previous.outputs.map(\.id))
        let added = current.outputs.filter { !previousIDs.contains($0.id) }
        if let defaultOutput = current.defaultBluetoothOutput, added.contains(defaultOutput) {
            return defaultOutput
        }
        if let first = added.first { return first }
        guard current.defaultOutputID != previous.defaultOutputID else { return nil }
        return current.defaultBluetoothOutput
    }

    /// Connecting usually fires "device added" and "default changed" back to back; report once.
    static func isDuplicate(name: String, lastTriggered: [String: Date], now: Date, window: TimeInterval) -> Bool {
        guard let last = lastTriggered[name] else { return false }
        return now.timeIntervalSince(last) < window
    }
}

/// Turkish labels: "Sol %80 · Sağ %75 · Kutu %40", or "Pil %60" for single-battery headsets.
enum HeadphoneBatteryFormatter {
    struct Part: Equatable, Sendable {
        let label: String
        let level: Int

        var text: String { "\(label) %\(level)" }
    }

    static func parts(_ levels: HeadphoneBatteryLevels) -> [Part] {
        let buds: [Part] = [
            levels.left.map { Part(label: "Sol", level: $0) },
            levels.right.map { Part(label: "Sağ", level: $0) },
            levels.caseLevel.map { Part(label: "Kutu", level: $0) },
        ].compactMap { $0 }
        if !buds.isEmpty { return buds }
        return levels.main.map { [Part(label: "Pil", level: $0)] } ?? []
    }

    static func subtitle(_ levels: HeadphoneBatteryLevels) -> String? {
        let text = parts(levels).map(\.text).joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    /// Lowest level, for the tile tint and glyph.
    static func lowest(_ levels: HeadphoneBatteryLevels) -> Int? {
        [levels.left, levels.right, levels.main].compactMap { $0 }.min() ?? levels.caseLevel
    }

    static func batteryGlyph(for level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    /// AirPods-aware device glyph, shared with the audio output picker.
    static func deviceGlyph(for name: String) -> String {
        AudioOutputDevice(id: 0, name: name, isDefault: false, transport: .bluetooth).systemImage
    }
}
