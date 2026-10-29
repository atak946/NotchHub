import SwiftUI

/// Content enters a beat after the notch morphs: blur → sharp, 0.96 → 1 and a slight lift.
private struct AlertEnterModifier: ViewModifier {
    static let blurRadius: CGFloat = 6
    static let scale: CGFloat = 0.96
    static let offset: CGFloat = 6

    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .blur(radius: isActive ? Self.blurRadius : 0)
            .scaleEffect(isActive ? Self.scale : 1, anchor: .top)
            .offset(y: isActive ? Self.offset : 0)
    }
}

extension AnyTransition {
    static let alertContentDelay = 0.12

    /// Cross-fade only when Reduce Motion is on.
    static func alertContent(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeInOut(duration: 0.2))
        }
        let insertion = AnyTransition.modifier(
            active: AlertEnterModifier(isActive: true),
            identity: AlertEnterModifier(isActive: false)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.86).delay(alertContentDelay))
        let removal = AnyTransition.modifier(
            active: AlertEnterModifier(isActive: true),
            identity: AlertEnterModifier(isActive: false)
        )
        .animation(.easeIn(duration: 0.14))
        return .asymmetric(insertion: insertion, removal: removal)
    }
}
