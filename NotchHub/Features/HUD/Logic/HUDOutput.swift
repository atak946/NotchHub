import Foundation

/// Headphones the volume HUD names: their glyph and, when a recent read exists, the lowest battery level.
struct HUDOutputDevice: Equatable, Sendable {
    let name: String
    let systemImage: String
    /// 0…100.
    let batteryPercent: Int?
}

/// Which outputs get their own glyph in the volume HUD, and when a battery read is still worth showing.
enum HUDOutputPolicy {
    /// Battery levels are only read on connect; older reads would show a stale value.
    static let batteryMaxAge: TimeInterval = 30 * 60

    /// Bluetooth outputs (AirPods, headphones) only; built-in, USB, HDMI and AirPlay keep the speaker.
    static func output(for device: AudioOutputDevice?, battery: HeadphoneBatteryReport?, now: Date) -> HUDOutputDevice? {
        guard let device, device.transport == .bluetooth else { return nil }
        return HUDOutputDevice(
            name: device.name,
            systemImage: device.systemImage,
            batteryPercent: batteryPercent(of: battery, deviceName: device.name, now: now)
        )
    }

    /// The lowest bud (or headset) level of a recent read for this device.
    static func batteryPercent(of report: HeadphoneBatteryReport?, deviceName: String, now: Date) -> Int? {
        guard let report, report.deviceName == deviceName, now.timeIntervalSince(report.readAt) <= batteryMaxAge,
              let lowest = HeadphoneBatteryFormatter.lowest(report.levels)
        else { return nil }
        return min(max(lowest, 0), 100)
    }
}
