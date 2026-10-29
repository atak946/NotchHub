import Foundation

/// Side-effecting execution of a single, already validated step.
@MainActor
protocol ProfileStepExecuting: AnyObject {
    /// Returns a short detail for the step result. Throws on failure, `CancellationError` on cancel.
    /// `prompt` asks the user for something (e.g. "Connect the VPN") through the notch.
    func execute(_ action: ProfileAction, prompt: @escaping @MainActor (ProfilePrompt) -> Void) async throws -> String?
}

struct ProfilePrompt: Equatable, Sendable {
    let title: String
    let subtitle: String
    let systemImage: String
}

struct ProfileStepFailure: Error, Equatable, Sendable, CustomStringConvertible {
    let message: String

    var description: String { message }
}

enum ProfileStepStatus: Equatable, Sendable {
    case succeeded(String?)
    case failed(String)
    /// Not run because an earlier critical step failed.
    case skipped
    case cancelled

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct ProfileStepResult: Equatable, Sendable, Identifiable {
    let stepID: UUID
    let summary: String
    let status: ProfileStepStatus

    var id: UUID { stepID }
}

struct ProfileRunReport: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case succeeded
        /// All critical steps succeeded, but some `continueOnFailure` steps failed.
        case succeededWithWarnings
        case failed
        case cancelled
    }

    let results: [ProfileStepResult]
    let outcome: Outcome

    var firstFailure: ProfileStepResult? {
        results.first { $0.status.isFailure }
    }
}

enum ProfileRunEvent: Equatable, Sendable {
    case stepStarted(index: Int, total: Int, summary: String)
    case stepFinished(ProfileStepResult)
}

/// Runs steps strictly in order: validate → execute → record. Stops at the first critical failure.
@MainActor
struct ProfileRunner {
    let executor: any ProfileStepExecuting
    let validator: ProfileStepValidator

    func run(
        _ steps: [ProfileStep],
        prompt: @escaping @MainActor (ProfilePrompt) -> Void = { _ in },
        onEvent: @MainActor (ProfileRunEvent) -> Void = { _ in }
    ) async -> ProfileRunReport {
        var results: [ProfileStepResult] = []
        var abortStatus: ProfileStepStatus?

        for (index, step) in steps.enumerated() {
            if abortStatus == nil, Task.isCancelled { abortStatus = .cancelled }
            if let abortStatus {
                results.append(ProfileStepResult(stepID: step.id, summary: step.action.summary, status: abortStatus))
                continue
            }
            onEvent(.stepStarted(index: index, total: steps.count, summary: step.action.summary))
            let status = await execute(step, prompt: prompt)
            let result = ProfileStepResult(stepID: step.id, summary: step.action.summary, status: status)
            results.append(result)
            onEvent(.stepFinished(result))

            switch status {
            case .cancelled:
                abortStatus = .cancelled
            case .failed:
                if !step.continueOnFailure { abortStatus = .skipped }
            case .succeeded, .skipped:
                break
            }
        }
        return ProfileRunReport(results: results, outcome: Self.outcome(results: results, abortStatus: abortStatus))
    }

    static func outcome(results: [ProfileStepResult], abortStatus: ProfileStepStatus?) -> ProfileRunReport.Outcome {
        switch abortStatus {
        case .cancelled: return .cancelled
        case .skipped: return .failed
        case .succeeded, .failed, nil: break
        }
        return results.contains { $0.status.isFailure } ? .succeededWithWarnings : .succeeded
    }

    private func execute(_ step: ProfileStep, prompt: @escaping @MainActor (ProfilePrompt) -> Void) async -> ProfileStepStatus {
        if let issue = validator.validate(step.action) {
            return .failed(issue.description)
        }
        do {
            let detail = try await executor.execute(step.action, prompt: prompt)
            return Task.isCancelled ? .cancelled : .succeeded(detail)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return Task.isCancelled ? .cancelled : .failed(String(describing: error))
        }
    }
}
