import SwiftUI

/// Toggle row: label leading, a switch tinted with the accent gradient trailing. Keyboard-focusable
/// (Space toggles) and presented to VoiceOver as a regular switch.
struct GlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassToggleRow(configuration: configuration)
    }
}

private struct GlassToggleRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: SettingsTheme.Spacing.m) {
                configuration.label
                    .font(SettingsTheme.Typography.row)
                    .foregroundStyle(SettingsTheme.Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                GlassSwitch(isOn: configuration.isOn)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// The switch knob and track.
struct GlassSwitch: View {
    private static let size = CGSize(width: 34, height: 20)
    private static let inset: CGFloat = 2

    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let knob = Self.size.height - Self.inset * 2
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(SettingsTheme.brandGradient) : AnyShapeStyle(SettingsTheme.Palette.controlFill))
                .overlay(Capsule().strokeBorder(.white.opacity(isOn ? 0.3 : 0.12), lineWidth: 0.5))
                .glassGlow(SettingsTheme.Palette.brand, opacity: isOn ? 0.45 : 0)
            Circle()
                .fill(.white)
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .padding(Self.inset)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(reduceMotion ? nil : SettingsTheme.Motion.press, value: isOn)
        .accessibilityHidden(true)
    }
}

/// `LabeledContent` as a row: label leading, value trailing in secondary text.
struct GlassLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsTheme.Spacing.m) {
            configuration.label
                .font(SettingsTheme.Typography.row)
                .foregroundStyle(SettingsTheme.Palette.textPrimary)
            Spacer(minLength: SettingsTheme.Spacing.m)
            configuration.content
                .font(SettingsTheme.Typography.row)
                .foregroundStyle(SettingsTheme.Palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Frosted glass capsule for row actions; destructive roles turn the label red.
struct GlassButtonStyle: ButtonStyle {
    private static let destructiveTint = Color(red: 1.0, green: 0.42, blue: 0.48)

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, destructiveTint: Self.destructiveTint)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let destructiveTint: Color
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(configuration.role == .destructive ? destructiveTint : SettingsTheme.Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(fillOpacity)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(isHovered ? 0.22 : 0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(SettingsTheme.Motion.press, value: configuration.isPressed)
            .animation(SettingsTheme.Motion.hover, value: isHovered)
            .onHover { isHovered = $0 }
            .contentShape(Capsule())
    }

    private var fillOpacity: Double {
        if configuration.isPressed { return 0.16 }
        return isHovered ? 0.11 : 0.06
    }
}

/// Compact page header: big, tight title and a one-line subtitle.
struct GlassPageHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: SettingsTheme.Spacing.m) {
            GlassIconTile(symbol: symbol, tint: tint, size: 38, glows: true)
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.xxs) {
                Text(title)
                    .font(SettingsTheme.Typography.pageTitle)
                    .tracking(SettingsTheme.Typography.displayTracking)
                    .foregroundStyle(SettingsTheme.textGradient)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(SettingsTheme.Typography.pageSubtitle)
                    .foregroundStyle(SettingsTheme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
