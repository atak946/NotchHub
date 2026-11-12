import CoreGraphics

/// Hit-testing for the collapsed "+N" status pill, which opens the panel on the Status tab.
extension NotchGeometry {
    /// The pill is tiny; a little slack makes it easy to aim at.
    static let overflowPillHitSlack: CGFloat = 4

    /// Converts a rect from the panel's hosting view (top-left origin) to screen coordinates (bottom-left origin).
    static func screenRect(ofViewRect rect: CGRect, inPanelFrame panelFrame: CGRect) -> CGRect {
        CGRect(
            x: panelFrame.minX + rect.minX,
            y: panelFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Whether `point` (screen coordinates) is on the pill drawn at `pillFrame` (hosting view coordinates).
    static func isOnOverflowPill(_ point: CGPoint, pillFrame: CGRect?, panelFrame: CGRect) -> Bool {
        guard let pillFrame, !pillFrame.isEmpty else { return false }
        let slack = overflowPillHitSlack
        return screenRect(ofViewRect: pillFrame, inPanelFrame: panelFrame)
            .insetBy(dx: -slack, dy: -slack)
            .contains(point)
    }
}
