import Foundation
import Testing
@testable import NotchHub

@MainActor
struct ProfileRunnerTests {
    private let executor = ProfilesFakeExecutor()

    private var runner: ProfileRunner {
        ProfileRunner(executor: executor, validator: makeProfilesPermissiveValidator())
    }

    private let steps = [
        ProfileStep(action: .openApp(bundleID: "com.example.vpn")),
        ProfileStep(action: .dockerComposeUp(path: "/w/acme")),
        ProfileStep(action: .openInVSCode(path: "/w/acme")),
    ]

    @Test func runsAllStepsInOrder() async {
        var events: [ProfileRunEvent] = []
        let report = await runner.run(steps, onEvent: { events.append($0) })

        #expect(executor.executed == steps.map(\.action))
        #expect(report.outcome == .succeeded)
        #expect(report.results.map(\.stepID) == steps.map(\.id))
        let started = events.compactMap { event -> Int? in
            if case let .stepStarted(index, total, _) = event, total == 3 { return index }
            return nil
        }
        #expect(started == [0, 1, 2])
    }

    @Test func criticalFailureSkipsRemainingSteps() async {
        executor.behavior = { action in
            action.kind == .dockerComposeUp ? .fail("compose broke") : .succeed(nil)
        }
        let report = await runner.run(steps)

        #expect(executor.executed.count == 2)
        #expect(report.outcome == .failed)
        #expect(report.results.map(\.status) == [.succeeded(nil), .failed("compose broke"), .skipped])
        #expect(report.firstFailure?.stepID == steps[1].id)
    }

    @Test func failureOnLastCriticalStepIsFailed() async {
        executor.behavior = { action in action.kind == .openInVSCode ? .fail("no code") : .succeed(nil) }
        let report = await runner.run(steps)
        #expect(report.outcome == .failed)
    }

    @Test func tolerantStepFailureContinues() async {
        var tolerant = steps
        tolerant[1].continueOnFailure = true
        executor.behavior = { action in action.kind == .dockerComposeUp ? .fail("compose broke") : .succeed("ok") }

        let report = await runner.run(tolerant)

        #expect(executor.executed.count == 3)
        #expect(report.outcome == .succeededWithWarnings)
    }

    @Test func invalidStepFailsWithoutExecuting() async {
        let strictRunner = ProfileRunner(executor: executor, validator: ProfileStepValidator(fileSystem: ProfilesFakeFileSystem()))
        let report = await strictRunner.run([ProfileStep(action: .openURL("file:///etc/hosts"))])

        #expect(executor.executed.isEmpty)
        #expect(report.outcome == .failed)
        #expect(report.results.first?.status == .failed(ProfileStepIssue.schemeNotAllowed("file").description))
    }

    @Test func cancellationStopsCurrentAndMarksRestCancelled() async {
        executor.behavior = { action in action.kind == .dockerComposeUp ? .hang : .succeed(nil) }
        let runner = self.runner
        let steps = self.steps
        let task = Task { await runner.run(steps) }

        await profilesWaitUntil { executor.hangStarted }
        task.cancel()
        let report = await task.value

        #expect(report.outcome == .cancelled)
        #expect(report.results.map(\.status) == [.succeeded(nil), .cancelled, .cancelled])
        #expect(executor.executed.count == 2)
    }

    @Test func cancelledBeforeStartRunsNothing() async {
        let runner = self.runner
        let steps = self.steps
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await runner.run(steps)
        }
        let report = await task.value
        #expect(executor.executed.isEmpty)
        #expect(report.outcome == .cancelled)
    }

    @Test func promptsAreForwarded() async {
        let prompt = ProfilePrompt(title: "Connect the VPN", subtitle: "Waiting", systemImage: "lock.shield")
        executor.behavior = { _ in .prompt(prompt) }
        var received: [ProfilePrompt] = []

        _ = await runner.run([ProfileStep(action: .waitForVPN(timeoutSeconds: 30))], prompt: { received.append($0) })

        #expect(received == [prompt])
    }
}
