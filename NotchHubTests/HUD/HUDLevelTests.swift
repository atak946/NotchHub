import Testing
@testable import NotchHub

struct HUDLevelTests {
    @Test(arguments: [(-0.5, 0.0), (0.0, 0.0), (0.42, 0.42), (1.0, 1.0), (1.7, 1.0)])
    func clampsToUnitRange(input: Double, expected: Double) {
        #expect(HUDLevel.clamped(input) == expected)
    }

    @Test func nanClampsToZero() {
        #expect(HUDLevel.clamped(.nan) == 0)
    }

    @Test(arguments: [(0.0, 0), (0.004, 0), (0.005, 1), (0.444, 44), (0.445, 45), (1.0, 100)])
    func roundsPercent(level: Double, expected: Int) {
        #expect(HUDLevel.percent(level) == expected)
    }

    @Test func readingClampsItsLevel() {
        #expect(HUDReading(kind: .volume, level: 1.3).level == 1)
        #expect(HUDReading(kind: .brightness, level: nil).level == nil)
    }

    @Test func valueTextPutsPercentFirstAndHandlesMuteAndUnknown() {
        #expect(HUDLevel.valueText(of: HUDReading(kind: .volume, level: 0.5)) == "%50")
        #expect(HUDLevel.valueText(of: HUDReading(kind: .volume, level: 0.5, isMuted: true)) == "Sessiz")
        #expect(HUDLevel.valueText(of: HUDReading(kind: .brightness, level: nil)) == "Parlaklık")
    }

    @Test func mutedVolumeShowsAnEmptyBarAndUnknownHasNone() {
        #expect(HUDLevel.displayedLevel(of: HUDReading(kind: .volume, level: 0.8, isMuted: true)) == 0)
        #expect(HUDLevel.displayedLevel(of: HUDReading(kind: .volume, level: 0.8)) == 0.8)
        #expect(HUDLevel.displayedLevel(of: HUDReading(kind: .keyboardBacklight, level: nil)) == nil)
    }

    @Test(arguments: [
        (0.0, false, "speaker.slash.fill"),
        (0.6, true, "speaker.slash.fill"),
        (0.2, false, "speaker.wave.1.fill"),
        (0.5, false, "speaker.wave.2.fill"),
        (0.9, false, "speaker.wave.3.fill"),
    ])
    func volumeIconFollowsLevel(level: Double, isMuted: Bool, expected: String) {
        #expect(HUDLevel.systemImage(of: HUDReading(kind: .volume, level: level, isMuted: isMuted)) == expected)
    }

    @Test func brightnessIconDimsBelowHalf() {
        #expect(HUDLevel.systemImage(of: HUDReading(kind: .brightness, level: 0.3)) == "sun.min.fill")
        #expect(HUDLevel.systemImage(of: HUDReading(kind: .brightness, level: 0.7)) == "sun.max.fill")
        #expect(HUDLevel.systemImage(of: HUDReading(kind: .brightness, level: nil)) == "sun.max.fill")
    }

    @Test func firstReadingOnlySetsTheBaseline() {
        #expect(!HUDLevel.isMeaningfulChange(from: nil, to: HUDReading(kind: .volume, level: 0.5)))
    }

    @Test func tinyFloatNoiseIsNotAChange() {
        let old = HUDReading(kind: .volume, level: 0.5)
        #expect(!HUDLevel.isMeaningfulChange(from: old, to: HUDReading(kind: .volume, level: 0.501)))
        #expect(HUDLevel.isMeaningfulChange(from: old, to: HUDReading(kind: .volume, level: 0.5625)))
    }

    @Test func muteToggleIsAChangeEvenAtTheSameLevel() {
        let old = HUDReading(kind: .volume, level: 0.5)
        #expect(HUDLevel.isMeaningfulChange(from: old, to: HUDReading(kind: .volume, level: 0.5, isMuted: true)))
    }
}
