import CoreGraphics

/// What one notch shows right now. Higher cases win; see `resolve`.
enum NotchPresentation: Equatable, Sendable {
    case collapsed
    /// Slim volume/brightness level; never takes clicks.
    case hud
    case alert
    case expanded
    /// Live camera preview; top priority so a running camera is always visible.
    case cameraMirror

    /// Priority: camera mirror > expanded panel > alert > HUD > collapsed.
    /// The HUD is the lowest overlay, so it never covers an alert or the open panel.
    static func resolve(
        isCameraMirrorShown: Bool,
        isExpanded: Bool,
        hasAlert: Bool,
        hasHUD: Bool
    ) -> NotchPresentation {
        if isCameraMirrorShown { return .cameraMirror }
        if isExpanded { return .expanded }
        if hasAlert { return .alert }
        if hasHUD { return .hud }
        return .collapsed
    }

    /// The only area of the window that may take clicks; `nil` keeps the whole window click-through.
    func interactiveRect(in geometry: NotchGeometry) -> CGRect? {
        switch self {
        case .expanded: geometry.expandedRect
        case .alert: geometry.alertRect
        case .cameraMirror: geometry.cameraMirrorRect
        case .hud, .collapsed: nil
        }
    }
}
