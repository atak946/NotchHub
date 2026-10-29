import SwiftUI

enum ProfilesMetrics {
    static let tileWidth: CGFloat = 140
    static let tileHeight: CGFloat = 70
    static let tileCornerRadius: CGFloat = 14
    static let tilePadding: CGFloat = 10
    static let dotSize: CGFloat = 8
    static let compactSize: CGFloat = 14
    static let chipHeight: CGFloat = 26
    static let pressedScale: CGFloat = 0.96
    static let animation = Animation.spring(duration: 0.22, bounce: 0.25)
}

extension ProfileColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .gray: .gray
        }
    }
}

/// Dark rounded tile surface with a tint wash and hover lift, shared by the Profiles status tiles.
struct ProfilesTileBackground: ViewModifier {
    let tint: Color
    let isHovered: Bool

    func body(content: Content) -> some View {
        content
            .padding(ProfilesMetrics.tilePadding)
            .frame(width: ProfilesMetrics.tileWidth, height: ProfilesMetrics.tileHeight, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: ProfilesMetrics.tileCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.12 : 0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: ProfilesMetrics.tileCornerRadius, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.28), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: ProfilesMetrics.tileCornerRadius, style: .continuous)
                            .strokeBorder(tint.opacity(isHovered ? 0.6 : 0.25), lineWidth: 1)
                    }
            }
            .foregroundStyle(.primary)
            .animation(ProfilesMetrics.animation, value: isHovered)
    }
}

extension View {
    func profilesTile(tint: Color, isHovered: Bool) -> some View {
        modifier(ProfilesTileBackground(tint: tint, isHovered: isHovered))
    }
}

struct ProfilesPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? ProfilesMetrics.pressedScale : 1)
            .animation(ProfilesMetrics.animation, value: configuration.isPressed)
    }
}
