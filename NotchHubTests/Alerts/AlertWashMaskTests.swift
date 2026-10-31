import CoreGraphics
import Testing
@testable import NotchHub

struct AlertWashMaskTests {
    @Test func clearThroughTheNotchThenFadesIn() {
        let stops = AlertAmbientWash.belowNotchStops(height: 100, notchHeight: 32, fade: 18)
        #expect(stops.map(\.location) == [0, 0.32, 0.5, 1])
        #expect(stops.map(\.opacity) == [0, 0, 1, 1])
    }

    @Test func noNotchKeepsTheWashEverywhere() {
        let stops = AlertAmbientWash.belowNotchStops(height: 100, notchHeight: 0, fade: 18)
        #expect(stops.allSatisfy { $0.opacity == 1 })
    }

    @Test func stopsStayInsideTheView() {
        let stops = AlertAmbientWash.belowNotchStops(height: 40, notchHeight: 32, fade: 18)
        #expect(stops.allSatisfy { (0...1).contains($0.location) })
        #expect(stops.map(\.location) == stops.map(\.location).sorted())
    }
}
