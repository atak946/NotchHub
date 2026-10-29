import Foundation
import Testing
@testable import NotchHub

@MainActor
struct PowerAwareLoopTests {
    private let power = StaticPowerConditions()
    private let sleeper = RecordingSleeper()

    private func makeLoop(priority: PollingPriority = .standard) -> PowerAwareLoop {
        PowerAwareLoop(priority: priority, power: power, sleep: sleeper.sleep)
    }

    @Test func runsImmediatelyThenSleepsTheScaledDelay() async {
        power.conditions = PowerConditions(isLowPowerMode: true)
        let loop = makeLoop()
        var runs = 0
        loop.start {
            runs += 1
            return .seconds(5)
        }
        await EnergyTestSupport.waitUntil { !sleeper.delays.isEmpty }
        #expect(runs == 1)
        #expect(sleeper.delays == [.seconds(10)])
        loop.stop()
        #expect(!loop.isActive)
    }

    @Test func kickRunsTheBodyAgainWithoutWaiting() async {
        let loop = makeLoop()
        var runs = 0
        loop.start {
            runs += 1
            return .seconds(30)
        }
        await EnergyTestSupport.waitUntil { runs == 1 && sleeper.delays.count == 1 }
        loop.kick()
        await EnergyTestSupport.waitUntil { runs == 2 }
        #expect(runs == 2)
        loop.stop()
    }

    @Test func nilIdlesUntilKicked() async {
        let loop = makeLoop()
        var runs = 0
        let switchBox = SwitchBox()
        loop.start {
            runs += 1
            return switchBox.isOn ? .seconds(1) : nil
        }
        await EnergyTestSupport.waitUntil { runs == 1 }
        await EnergyTestSupport.waitUntil { false }
        #expect(sleeper.delays.isEmpty)
        #expect(loop.isActive)
        switchBox.isOn = true
        loop.kick()
        await EnergyTestSupport.waitUntil { sleeper.delays.count == 1 }
        #expect(runs == 2)
        #expect(sleeper.delays == [.seconds(1)])
        loop.stop()
    }

    @Test func resumeSignalKicksTheLoop() async {
        let loop = makeLoop()
        var runs = 0
        loop.start {
            runs += 1
            return .seconds(60)
        }
        await EnergyTestSupport.waitUntil { sleeper.delays.count == 1 }
        power.resume()
        await EnergyTestSupport.waitUntil { runs == 2 }
        #expect(runs == 2)
        loop.stop()
    }

    @Test func stoppedLoopIgnoresKicksAndStartIsIdempotent() async {
        let loop = makeLoop()
        var runs = 0
        loop.start {
            runs += 1
            return .seconds(1)
        }
        loop.start {
            runs += 100
            return .seconds(1)
        }
        await EnergyTestSupport.waitUntil { runs >= 1 }
        loop.stop()
        loop.kick()
        await EnergyTestSupport.waitUntil { false }
        #expect(runs == 1)
    }

    @Test func criticalLoopIgnoresAwayScaling() async {
        power.conditions = PowerConditions(isScreenAsleep: true)
        let loop = makeLoop(priority: .critical)
        loop.start { .seconds(5) }
        await EnergyTestSupport.waitUntil { !sleeper.delays.isEmpty }
        #expect(sleeper.delays == [.seconds(5)])
        #expect(loop.scaledDelay(for: .seconds(5)) == .seconds(5))
        loop.stop()
    }
}

@MainActor
private final class SwitchBox {
    var isOn = false
}
