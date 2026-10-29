import Foundation

/// The wizard's pages, in display order.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case permissions
    case calendarSources
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: String(localized: "Hoş geldin")
        case .permissions: String(localized: "İzinler")
        case .calendarSources: String(localized: "Takvim kaynakları")
        case .done: String(localized: "Hazır")
        }
    }
}

/// Pure step navigation for the onboarding wizard. Every transition returns a new value.
struct OnboardingFlow: Equatable, Sendable {
    let step: OnboardingStep

    init(step: OnboardingStep = .welcome) {
        self.step = step
    }

    static var stepCount: Int { OnboardingStep.allCases.count }

    var isFirstStep: Bool { step == OnboardingStep.allCases.first }
    var isLastStep: Bool { step == OnboardingStep.allCases.last }
    var canGoBack: Bool { !isFirstStep }

    /// 1-based position, for "2 / 4" labels.
    var stepNumber: Int { step.rawValue + 1 }

    /// 0...1, the share of the wizard reached so far.
    var progress: Double {
        Double(stepNumber) / Double(Self.stepCount)
    }

    var primaryButtonTitle: String {
        switch step {
        case .welcome: String(localized: "Başla")
        case .permissions, .calendarSources: String(localized: "Devam")
        case .done: String(localized: "Bitir")
        }
    }

    /// The next step, or the same flow when already on the last one.
    func advanced() -> OnboardingFlow {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return self }
        return OnboardingFlow(step: next)
    }

    /// The previous step, or the same flow when already on the first one.
    func retreated() -> OnboardingFlow {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return self }
        return OnboardingFlow(step: previous)
    }
}
