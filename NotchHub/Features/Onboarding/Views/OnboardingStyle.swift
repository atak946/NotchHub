import SwiftUI

/// Design tokens for the wizard: the notch's black glass with a cool accent.
enum OnboardingStyle {
    static let windowSize = CGSize(width: 620, height: 560)
    static let accent = Color(red: 0.42, green: 0.62, blue: 1.0)
    static let accentSecondary = Color(red: 0.66, green: 0.48, blue: 1.0)
    static let granted = Color(red: 0.36, green: 0.85, blue: 0.55)
    static let denied = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let pending = Color(white: 0.62)
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.09)
    static let secondaryText = Color.white.opacity(0.62)
    static let cardRadius: CGFloat = 14
    static let contentPadding: CGFloat = 32
    static let rowSpacing: CGFloat = 8

    static func color(for status: PermissionStatus) -> Color {
        switch status {
        case .granted: granted
        case .notDetermined: pending
        case .denied: denied
        }
    }

    static func symbol(for status: PermissionStatus) -> String {
        switch status {
        case .granted: "checkmark.circle.fill"
        case .notDetermined: "circle.dashed"
        case .denied: "xmark.circle.fill"
        }
    }
}

/// Deep backdrop: near-black with two soft accent washes, like light leaking from the notch.
struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            Color(white: 0.04)
            RadialGradient(
                colors: [OnboardingStyle.accent.opacity(0.22), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 360
            )
            RadialGradient(
                colors: [OnboardingStyle.accentSecondary.opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Frosted card surface used for rows and hints.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial.opacity(0.35), in: .rect(cornerRadius: OnboardingStyle.cardRadius))
            .background(OnboardingStyle.cardFill, in: .rect(cornerRadius: OnboardingStyle.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: OnboardingStyle.cardRadius)
                    .strokeBorder(OnboardingStyle.cardStroke, lineWidth: 0.5)
            }
    }
}

/// Page heading: a large title with a muted one-line subtitle.
struct OnboardingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Accent capsule button for the primary action.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [OnboardingStyle.accent, OnboardingStyle.accentSecondary],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: .capsule
            )
            .shadow(color: OnboardingStyle.accent.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 10, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quiet glass capsule for secondary actions.
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.08), in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
    }
}
