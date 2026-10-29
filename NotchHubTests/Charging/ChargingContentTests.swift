import Foundation
import Testing
@testable import NotchHub

struct PowerSnapshotParserTests {
    private typealias Key = PowerSnapshotParser.Key

    private static func description(
        type: String = PowerSnapshotParser.internalBatteryType,
        current: Int = 62,
        max: Int = 100,
        state: String = PowerSnapshotParser.acPowerValue,
        charging: Bool = true,
        minutes: Int = 80
    ) -> [String: Any] {
        [
            Key.type: type,
            Key.isPresent: true,
            Key.currentCapacity: current,
            Key.maxCapacity: max,
            Key.powerSourceState: state,
            Key.isCharging: charging,
            Key.timeToFull: minutes,
        ]
    }

    @Test func parsesChargingBattery() {
        let snapshot = PowerSnapshotParser.snapshot(from: Self.description())
        #expect(snapshot == PowerSnapshot(percent: 62, isPluggedIn: true, isCharging: true, minutesToFull: 80))
    }

    @Test func calculatingTimeToFullIsNil() {
        #expect(PowerSnapshotParser.snapshot(from: Self.description(minutes: -1))?.minutesToFull == nil)
    }

    @Test func dischargingHasNoTimeToFull() {
        let snapshot = PowerSnapshotParser.snapshot(from: Self.description(state: "Battery Power", charging: false))
        #expect(snapshot?.isPluggedIn == false)
        #expect(snapshot?.minutesToFull == nil)
    }

    @Test func scalesNonPercentCapacity() {
        #expect(PowerSnapshotParser.snapshot(from: Self.description(current: 2500, max: 5000))?.percent == 50)
    }

    @Test func ignoresNonBatterySources() {
        #expect(PowerSnapshotParser.snapshot(from: Self.description(type: "UPS")) == nil)
        #expect(PowerSnapshotParser.snapshot(from: Self.description(max: 0)) == nil)
        #expect(PowerSnapshotParser.snapshot(from: [:]) == nil)
    }
}

struct ChargingAlertContentTests {
    private static let turkish = Locale(identifier: "tr_TR")
    private static let english = Locale(identifier: "en_US")

    @Test func formatsPercentPerLocale() {
        #expect(ChargingAlertContent.percentText(62, locale: Self.turkish) == "%62")
        #expect(ChargingAlertContent.percentText(62, locale: Self.english) == "62%")
    }

    @Test func formatsTimeToFull() {
        #expect(ChargingAlertContent.timeToFullText(minutes: 80) == "Dolmasına 1 sa 20 dk")
        #expect(ChargingAlertContent.durationText(minutes: 45) == "45 dk")
        #expect(ChargingAlertContent.durationText(minutes: 120) == "2 sa")
    }

    @Test func chargingContent() {
        let snapshot = PowerSnapshot(percent: 62, isPluggedIn: true, isCharging: true, minutesToFull: 80)
        let content = ChargingAlertContent(event: ChargingEvent(kind: .charging, snapshot: snapshot), locale: Self.turkish)
        #expect(content.style == .success)
        #expect(content.glyph == AlertBatteryGlyph(level: 0.62, state: .charging))
        #expect(content.subtitle?.hasPrefix("%62") == true)
        #expect(content.duration == ChargingAlertContent.presentationDuration)
    }

    @Test func chargingWithoutEstimateShowsOnlyPercent() {
        let snapshot = PowerSnapshot(percent: 40, isPluggedIn: true, isCharging: true)
        let content = ChargingAlertContent(event: ChargingEvent(kind: .charging, snapshot: snapshot), locale: Self.turkish)
        #expect(content.subtitle == "%40")
    }

    @Test func unpluggedContentHasNoSubtitle() {
        let snapshot = PowerSnapshot(percent: 62, isPluggedIn: false, isCharging: false)
        let content = ChargingAlertContent(event: ChargingEvent(kind: .unplugged, snapshot: snapshot), locale: Self.turkish)
        #expect(content.subtitle == nil)
        #expect(content.title.contains("%62"))
        #expect(content.glyph.state == .discharging)
    }

    @Test func tenPercentIsUrgentTwentyIsReminder() {
        let snapshot = PowerSnapshot(percent: 10, isPluggedIn: false, isCharging: false)
        let urgent = ChargingAlertContent(event: ChargingEvent(kind: .lowBattery(threshold: 10), snapshot: snapshot))
        let reminder = ChargingAlertContent(event: ChargingEvent(kind: .lowBattery(threshold: 20), snapshot: snapshot))
        #expect(urgent.style == .urgent)
        #expect(reminder.style == .reminder)
        #expect(urgent.duration == ChargingAlertContent.warningDuration)
    }

    @Test(arguments: [(1.0, "battery.100percent"), (0.6, "battery.50percent"), (0.1, "battery.0percent")])
    func glyphSymbolFollowsLevel(level: Double, symbol: String) {
        #expect(AlertBatteryGlyph(level: level, state: .discharging).systemImage == symbol)
        #expect(AlertBatteryGlyph(level: level, state: .charging).systemImage == "bolt.fill")
    }
}
