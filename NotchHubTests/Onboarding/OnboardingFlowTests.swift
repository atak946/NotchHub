import Foundation
import Testing
@testable import NotchHub

struct OnboardingPolicyTests {
    @Test(arguments: [
        (nil as Int?, 1, true),
        (0, 1, true),
        (1, 1, false),
        (2, 1, false),
        (1, 2, true),
    ])
    func decision(stored: Int?, current: Int, expected: Bool) {
        #expect(OnboardingPolicy.shouldShow(storedVersion: stored, currentVersion: current) == expected)
    }

    @MainActor
    @Test func storeMarksCompletedAndNeverDowngrades() throws {
        let (suite, defaults) = TestDefaults.makeSuite("OnboardingPolicyTests.\(UUID().uuidString)")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults)

        #expect(store.completedVersion == nil)
        #expect(store.shouldShowOnLaunch)

        store.markCompleted(version: 3)
        store.markCompleted(version: 1)

        #expect(store.completedVersion == 3)
        #expect(!store.shouldShowOnLaunch)
    }
}

struct OnboardingFlowTests {
    @Test func startsOnWelcome() {
        let flow = OnboardingFlow()
        #expect(flow.step == .welcome)
        #expect(flow.isFirstStep)
        #expect(!flow.canGoBack)
        #expect(flow.primaryButtonTitle == "Başla")
        #expect(flow.stepNumber == 1)
    }

    @Test func advancesThroughEveryStepInOrder() {
        var flow = OnboardingFlow()
        var visited = [flow.step]
        while !flow.isLastStep {
            flow = flow.advanced()
            visited.append(flow.step)
        }
        #expect(visited == [.welcome, .permissions, .calendarSources, .done])
        #expect(flow.primaryButtonTitle == "Bitir")
        #expect(flow.progress == 1)
    }

    @Test func advancingPastTheEndAndRetreatingBeforeTheStartAreNoOps() {
        let last = OnboardingFlow(step: .done)
        #expect(last.advanced() == last)
        let first = OnboardingFlow()
        #expect(first.retreated() == first)
    }

    @Test func retreatGoesBackOneStep() {
        let flow = OnboardingFlow(step: .calendarSources).retreated()
        #expect(flow.step == .permissions)
        #expect(flow.canGoBack)
        #expect(flow.primaryButtonTitle == "Devam")
    }

    @Test func transitionsDoNotMutateTheOriginal() {
        let flow = OnboardingFlow()
        _ = flow.advanced()
        #expect(flow.step == .welcome)
    }

    @Test func progressGrowsWithEachStep() {
        let values = OnboardingStep.allCases.map { OnboardingFlow(step: $0).progress }
        #expect(values == values.sorted())
        #expect(values.first == 0.25)
    }
}
