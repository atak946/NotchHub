import CoreGraphics

/// Layout and hit-testing for the meeting mic button at the inner end of the right wing.
extension NotchGeometry {
    static let micMuteButtonWidth: CGFloat = 22
    /// Gap between the notch's right edge and the button.
    static let micMuteNotchInset: CGFloat = 4
    /// Right wing width while the button shares it with the meeting timer and status glyphs.
    static let micMuteWingWidth: CGFloat = 112
    /// Extends the hit area above the screen so the very top pixel row counts, like the hot zone.
    private static let micMuteTopEdgeAllowance: CGFloat = 1

    /// The button in screen coordinates, full notch height; nil when the wing is too narrow.
    func micMuteButtonRect(wingWidth: CGFloat) -> CGRect? {
        let width = Self.micMuteButtonWidth
        guard wingWidth >= width + Self.micMuteNotchInset else { return nil }
        let collapsed = collapsedRect(wingWidth: wingWidth)
        let notchMaxX = collapsed.maxX - wingWidth
        return CGRect(
            x: notchMaxX + Self.micMuteNotchInset,
            y: collapsed.minY,
            width: width,
            height: collapsed.height
        )
    }

    /// Hit test: the button rect plus the top pixel row.
    func isOnMicMuteButton(_ point: CGPoint, wingWidth: CGFloat) -> Bool {
        guard let rect = micMuteButtonRect(wingWidth: wingWidth) else { return false }
        let hitRect = CGRect(
            x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + Self.micMuteTopEdgeAllowance
        )
        return hitRect.contains(point)
    }
}

/// Pure visibility rules for the collapsed meeting mic button.
enum CompactMicMute {
    /// Part of the collapsed layout: only during a detected meeting with a controllable input device.
    static func isAvailable(isInMeeting: Bool, isControlAvailable: Bool) -> Bool {
        isInMeeting && isControlAvailable
    }

    /// Takes clicks and blocks hover-to-open right now.
    static func isInteractive(isAvailable: Bool, isAlertShowing: Bool, isExpanded: Bool) -> Bool {
        isAvailable && !isAlertShowing && !isExpanded
    }

    /// Wing width with the button: never narrower than what the other wing content needs.
    static func wingWidth(base: CGFloat, isAvailable: Bool) -> CGFloat {
        isAvailable ? max(base, NotchGeometry.micMuteWingWidth) : base
    }
}
