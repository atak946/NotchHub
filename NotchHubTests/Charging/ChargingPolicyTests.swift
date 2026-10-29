import Foundation
import Testing
@testable import NotchHub

struct ChargingPolicyTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let allOn = ChargingPreferences(showsCharging: true, warnsLowBattery: true)

    private static func battery(_ percent: Int, charging: Bool = false) -> PowerSnapshot {
        PowerSnapshot(percent: percent, isPluggedIn: false, isCharging: charging)
    }

    private static func plugged(_ percent: Int, charging: Bool = true, charged: Bool = false) -> PowerSnapshot {
        PowerSnapshot(percent: percent, isPluggedIn: true, isCharging: charging, isCharged: charged, minutesToFull: 80)
    }

    /// Feeds readings in order (one second apart) and returns the presented event kinds.
    private static func run(
        _ readings: [PowerSnapshot?],
        preferences: ChargingPreferences = allOn,
        spacing: TimeInterval = 1
    ) -> [ChargingEvent.Kind] {
        var state = ChargingPolicyState.initial
        var kinds: [ChargingEvent.Kind] = []
        for (index, reading) in readings.enumerated() {
            let now = start.addingTimeInterval(Double(index) * spacing)
            let decision = ChargingPolicy.evaluate(reading, state: state, now: now, preferences: preferences)
            state = decision.state
            if let event = decision.event { kinds.append(event.kind) }
        }
        return kinds
    }

    @Test func firstReadingIsOnlyABaseline() {
        #expect(Self.run([Self.plugged(50)]).isEmpty)
        #expect(Self.run([Self.battery(5)]).isEmpty)
    }

    @Test func noBatteryShowsNothing() {
        #expect(Self.run([nil, nil, nil]).isEmpty)
    }

    @Test func plugInShowsCharging() {
        #expect(Self.run([Self.battery(62), Self.plugged(62)]) == [.charging])
    }

    @Test func plugInCarriesTheNewSnapshot() {
        let decision = ChargingPolicy.evaluate(
            Self.plugged(62),
            state: ChargingPolicyState(baseline: Self.battery(62)),
            now: Self.start,
            preferences: Self.allOn
        )
        #expect(decision.event == ChargingEvent(kind: .charging, snapshot: Self.plugged(62)))
    }

    @Test func unplugShowsBatteryVariant() {
        #expect(Self.run([Self.plugged(62), Self.battery(62)]) == [.unplugged])
    }

    @Test func chargingStartWhilePluggedShowsCharging() {
        #expect(Self.run([Self.plugged(80, charging: false), Self.plugged(80, charging: true)]) == [.charging])
    }

    @Test func flappingAdapterDoesNotRepeat() {
        let readings = [Self.battery(50), Self.plugged(50), Self.battery(50), Self.plugged(50), Self.battery(50)]
        #expect(Self.run(readings) == [.charging, .unplugged])
    }

    @Test func plugInRepeatsAfterCooldown() {
        let readings = [Self.battery(50), Self.plugged(50), Self.battery(50), Self.plugged(50)]
        let spacing = ChargingPolicy.repeatCooldown
        #expect(Self.run(readings, spacing: spacing) == [.charging, .unplugged, .charging])
    }

    @Test func fullyChargedShowsOncePerPlugIn() {
        let readings = [
            Self.battery(97), Self.plugged(97), Self.plugged(99), Self.plugged(100, charging: false, charged: true),
            Self.plugged(99, charging: false), Self.plugged(100, charging: false, charged: true),
        ]
        #expect(Self.run(readings) == [.charging, .fullyCharged])
    }

    @Test func pluggingInWhenFullDoesNotAlsoAnnounceFull() {
        let readings = [Self.battery(100), Self.plugged(100, charging: false, charged: true), Self.plugged(100, charging: false, charged: true)]
        #expect(Self.run(readings) == [.charging])
    }

    @Test func launchingPluggedAndFullStaysQuiet() {
        #expect(Self.run([Self.plugged(100, charging: false, charged: true), Self.plugged(100, charging: false)]).isEmpty)
    }

    @Test func lowBatteryWarnsAtTwentyAndTen() {
        let readings = [Self.battery(22), Self.battery(21), Self.battery(20), Self.battery(15), Self.battery(10), Self.battery(9)]
        #expect(Self.run(readings) == [.lowBattery(threshold: 20), .lowBattery(threshold: 10)])
    }

    @Test func lowBatteryDoesNotRepeatOnJitter() {
        let readings = [Self.battery(21), Self.battery(20), Self.battery(21), Self.battery(20)]
        #expect(Self.run(readings) == [.lowBattery(threshold: 20)])
    }

    @Test func skippingBothThresholdsShowsTheMostUrgent() {
        #expect(Self.run([Self.battery(25), Self.battery(8), Self.battery(7)]) == [.lowBattery(threshold: 10)])
    }

    @Test func launchingBelowThresholdDoesNotWarnForIt() {
        #expect(Self.run([Self.battery(15), Self.battery(14), Self.battery(10)]) == [.lowBattery(threshold: 10)])
    }

    @Test func unplugBelowTwentyOnlyWarnsAtTen() {
        let readings = [Self.plugged(15), Self.battery(15), Self.battery(12), Self.battery(10)]
        #expect(Self.run(readings) == [.unplugged, .lowBattery(threshold: 10)])
    }

    @Test func pluggingInResetsLowWarnings() {
        let readings = [
            Self.battery(21), Self.battery(20), Self.plugged(20), Self.plugged(25), Self.battery(25), Self.battery(20),
        ]
        let spacing = ChargingPolicy.repeatCooldown
        #expect(Self.run(readings, spacing: spacing) == [
            .lowBattery(threshold: 20), .charging, .unplugged, .lowBattery(threshold: 20),
        ])
    }

    @Test func chargingWhileLowNeverWarns() {
        #expect(Self.run([Self.plugged(21), Self.plugged(20), Self.plugged(10)]).isEmpty)
    }

    @Test func chargingToggleOffSilencesPowerPresentations() {
        let preferences = ChargingPreferences(showsCharging: false, warnsLowBattery: true)
        let readings = [Self.battery(50), Self.plugged(50), Self.battery(21), Self.battery(20)]
        #expect(Self.run(readings, preferences: preferences) == [.lowBattery(threshold: 20)])
    }

    @Test func lowBatteryToggleOffSilencesWarnings() {
        let preferences = ChargingPreferences(showsCharging: true, warnsLowBattery: false)
        #expect(Self.run([Self.battery(21), Self.battery(20), Self.battery(10)], preferences: preferences).isEmpty)
    }

    @Test func batteryDisappearingResetsState() {
        #expect(Self.run([Self.battery(50), nil, Self.plugged(50)]).isEmpty)
    }
}
