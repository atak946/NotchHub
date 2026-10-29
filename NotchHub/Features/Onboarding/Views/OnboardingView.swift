import OSLog
import SwiftUI

/// Root of the wizard: the current page plus a footer with progress dots and navigation.
struct OnboardingView: View {
    let permissions: PermissionsModel
    let onFinish: () -> Void

    @State private var flow = OnboardingFlow()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Onboarding")

    var body: some View {
        VStack(spacing: 0) {
            page
                .id(flow.step)
                .transition(pageTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, OnboardingStyle.contentPadding)
                .padding(.top, 44)
            footer
                .padding(.horizontal, OnboardingStyle.contentPadding)
                .padding(.bottom, 24)
        }
        .frame(width: OnboardingStyle.windowSize.width, height: OnboardingStyle.windowSize.height)
        .background(OnboardingBackdrop())
        .preferredColorScheme(.dark)
        .onChange(of: launchAtLogin) { _, newValue in updateLaunchAtLogin(newValue) }
    }

    @ViewBuilder
    private var page: some View {
        switch flow.step {
        case .welcome: OnboardingWelcomeStep()
        case .permissions: OnboardingPermissionsStep(permissions: permissions)
        case .calendarSources: OnboardingCalendarSourcesStep()
        case .done: OnboardingDoneStep(launchAtLogin: $launchAtLogin, launchAtLoginError: launchAtLoginError)
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 24)),
            removal: .opacity.combined(with: .offset(x: -24))
        )
    }

    private var footer: some View {
        HStack {
            Button("Geri") { move(to: flow.retreated()) }
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .opacity(flow.canGoBack ? 1 : 0)
                .disabled(!flow.canGoBack)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            ProgressDots(flow: flow)
            Spacer()
            Button(flow.primaryButtonTitle) {
                if flow.isLastStep {
                    onFinish()
                } else {
                    move(to: flow.advanced())
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func move(to next: OnboardingFlow) {
        withAnimation(.smooth(duration: 0.35)) { flow = next }
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        guard isEnabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.setEnabled(isEnabled)
            launchAtLoginError = nil
        } catch {
            logger.error("Launch at login update failed: \(error.localizedDescription, privacy: .public)")
            launchAtLoginError = "Giriş öğesi güncellenemedi: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct ProgressDots: View {
    let flow: OnboardingFlow

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
                Capsule()
                    .fill(step == flow.step ? OnboardingStyle.accent : .white.opacity(step.rawValue < flow.step.rawValue ? 0.45 : 0.15))
                    .frame(width: step == flow.step ? 20 : 6, height: 6)
            }
        }
        .animation(.snappy, value: flow.step)
        .accessibilityElement()
        .accessibilityLabel("Adım \(flow.stepNumber) / \(OnboardingFlow.stepCount)")
    }
}
