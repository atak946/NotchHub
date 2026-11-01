import Foundation
import Testing
@testable import NotchHub

struct HUDInteractionTests {
    // MARK: - Scroll

    @Test func scrollingUpRaisesTheLevelWithOrWithoutNaturalScrolling() {
        // Natural scrolling reports a finger swipe up as a negative delta.
        let natural = HUDInteractionMath.scrolled(0.5, deltaY: -24, isPrecise: true, isInverted: true)
        let classic = HUDInteractionMath.scrolled(0.5, deltaY: 24, isPrecise: true, isInverted: false)

        #expect(abs(natural - 0.6) < 1e-9)
        #expect(abs(classic - 0.6) < 1e-9)
    }

    @Test func mouseWheelNotchesMoveOneMacOSStep() {
        #expect(HUDInteractionMath.scrolled(0.5, deltaY: 1, isPrecise: false, isInverted: false) == 0.5 + 1.0 / 16)
        #expect(HUDInteractionMath.scrolled(0.5, deltaY: -2, isPrecise: false, isInverted: false) == 0.5 - 2.0 / 16)
    }

    @Test func scrollingClampsAtTheEnds() {
        #expect(HUDInteractionMath.scrolled(0.95, deltaY: 400, isPrecise: true, isInverted: false) == 1)
        #expect(HUDInteractionMath.scrolled(0.05, deltaY: -5, isPrecise: false, isInverted: false) == 0)
    }

    // MARK: - Drag

    @Test(arguments: [(4.0, 0.0), (54.0, 0.5), (104.0, 1.0), (0.0, 0.0), (130.0, 1.0)])
    func dragPositionMapsOntoTheBar(x: Double, expected: Double) {
        #expect(HUDInteractionMath.level(atX: x, barWidth: 100, inset: 4) == expected)
    }

    @Test func zeroWidthBarReadsAsEmpty() {
        #expect(HUDInteractionMath.level(atX: 20, barWidth: 0, inset: 0) == 0)
    }

    @Test func keyboardBacklightCannotBeAdjusted() {
        #expect(HUDInteractionMath.isAdjustable(.volume))
        #expect(HUDInteractionMath.isAdjustable(.brightness))
        #expect(!HUDInteractionMath.isAdjustable(.keyboardBacklight))
    }

    // MARK: - Tint

    @Test func barTakesTheArtworkColourOnlyWhilePlaying() {
        let teal = RGBColor(red: 0.2, green: 0.8, blue: 0.75)

        #expect(HUDAccent.barTint(isPlaying: true, artworkTint: teal) == teal)
        #expect(HUDAccent.barTint(isPlaying: false, artworkTint: teal) == .white)
        #expect(HUDAccent.barTint(isPlaying: true, artworkTint: nil) == .white)
    }

    // MARK: - Bounce

    @Test func bouncesOnArrivingAtAnEnd() {
        #expect(HUDBouncePolicy.shouldBounce(edge: .full, previousEdge: nil, isDragging: true, sinceLastBounce: .zero))
        #expect(HUDBouncePolicy.shouldBounce(edge: .empty, previousEdge: .full, isDragging: false, sinceLastBounce: .zero))
        #expect(!HUDBouncePolicy.shouldBounce(edge: nil, previousEdge: .full, isDragging: false, sinceLastBounce: nil))
    }

    @Test func repeatedPressesAgainstAnEndReplayTheBounceButNotEveryDragUpdate() {
        let later = HUDBouncePolicy.minimumInterval
        let soon = Duration.milliseconds(50)

        #expect(HUDBouncePolicy.shouldBounce(edge: .full, previousEdge: .full, isDragging: false, sinceLastBounce: later))
        #expect(HUDBouncePolicy.shouldBounce(edge: .full, previousEdge: .full, isDragging: false, sinceLastBounce: nil))
        #expect(!HUDBouncePolicy.shouldBounce(edge: .full, previousEdge: .full, isDragging: false, sinceLastBounce: soon))
        #expect(!HUDBouncePolicy.shouldBounce(edge: .full, previousEdge: .full, isDragging: true, sinceLastBounce: later))
    }

    // MARK: - Output device

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func device(_ name: String, _ transport: AudioTransportKind) -> AudioOutputDevice {
        AudioOutputDevice(id: 7, name: name, isDefault: true, transport: transport)
    }

    private func report(_ name: String, left: Int?, right: Int?, main: Int? = nil, age: TimeInterval = 60) -> HeadphoneBatteryReport {
        HeadphoneBatteryReport(
            deviceName: name,
            levels: HeadphoneBatteryLevels(left: left, right: right, caseLevel: 90, main: main),
            readAt: now.addingTimeInterval(-age)
        )
    }

    @Test func airPodsGetTheirGlyphAndLowestBudBattery() {
        let output = HUDOutputPolicy.output(
            for: device("AirPods Pro", .bluetooth),
            battery: report("AirPods Pro", left: 80, right: 65),
            now: now
        )

        #expect(output == HUDOutputDevice(name: "AirPods Pro", systemImage: "airpodspro", batteryPercent: 65))
    }

    @Test func bluetoothHeadsetWithoutAReadShowsNoBattery() {
        let output = HUDOutputPolicy.output(for: device("WH-1000XM5", .bluetooth), battery: nil, now: now)

        #expect(output == HUDOutputDevice(name: "WH-1000XM5", systemImage: "headphones", batteryPercent: nil))
    }

    @Test(arguments: [AudioTransportKind.builtIn, .usb, .hdmi, .airPlay, .other])
    func otherOutputsKeepTheSpeaker(transport: AudioTransportKind) {
        #expect(HUDOutputPolicy.output(for: device("Output", transport), battery: nil, now: now) == nil)
    }

    @Test func noDefaultDeviceKeepsTheSpeaker() {
        #expect(HUDOutputPolicy.output(for: nil, battery: nil, now: now) == nil)
    }

    @Test func batteryOfAnotherDeviceOrAnOldReadIsNotShown() {
        #expect(HUDOutputPolicy.batteryPercent(of: report("Other", left: 50, right: 50), deviceName: "AirPods", now: now) == nil)
        let old = report("AirPods", left: 50, right: 50, age: HUDOutputPolicy.batteryMaxAge + 1)
        #expect(HUDOutputPolicy.batteryPercent(of: old, deviceName: "AirPods", now: now) == nil)
        let single = report("Headset", left: nil, right: nil, main: 42)
        #expect(HUDOutputPolicy.batteryPercent(of: single, deviceName: "Headset", now: now) == 42)
    }
}
