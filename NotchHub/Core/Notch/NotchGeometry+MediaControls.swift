import CoreGraphics

/// Layout and hit-testing for the media controls box at the inner end of the left wing.
extension NotchGeometry {
    /// Wing width while the controls show: artwork, gap and the three buttons.
    static let mediaControlsWingWidth: CGFloat = 104
    static let mediaControlButtonWidth: CGFloat = 24
    static let mediaControlsBoxHeight: CGFloat = 22
    /// Gap between the controls box and the notch's left edge.
    static let mediaControlsNotchInset: CGFloat = 4
    /// Extends hit areas above the screen so the very top pixel row counts, like the hot zone.
    private static let topEdgeAllowance: CGFloat = 1

    static var mediaControlsWidth: CGFloat {
        mediaControlButtonWidth * CGFloat(MediaControlAction.allCases.count)
    }

    /// The controls box in screen coordinates, full notch height; nil when the wing is too narrow.
    func mediaControlsRect(wingWidth: CGFloat) -> CGRect? {
        let width = Self.mediaControlsWidth
        guard wingWidth >= width + Self.mediaControlsNotchInset else { return nil }
        let collapsed = collapsedRect(wingWidth: wingWidth)
        let notchMinX = collapsed.minX + wingWidth
        return CGRect(
            x: notchMinX - Self.mediaControlsNotchInset - width,
            y: collapsed.minY,
            width: width,
            height: collapsed.height
        )
    }

    /// One contiguous hit rect per button, left to right.
    func mediaControlRects(wingWidth: CGFloat) -> [(action: MediaControlAction, rect: CGRect)] {
        guard let box = mediaControlsRect(wingWidth: wingWidth) else { return [] }
        let buttonWidth = Self.mediaControlButtonWidth
        return MediaControlAction.allCases.enumerated().map { index, action in
            let rect = CGRect(
                x: box.minX + CGFloat(index) * buttonWidth,
                y: box.minY,
                width: buttonWidth,
                height: box.height + Self.topEdgeAllowance
            )
            return (action, rect)
        }
    }

    func mediaControlAction(at point: CGPoint, wingWidth: CGFloat) -> MediaControlAction? {
        mediaControlRects(wingWidth: wingWidth).first { $0.rect.contains(point) }?.action
    }

    /// Hover-to-open trigger; the controls box never starts the open timer while it is interactive.
    func shouldOpen(at point: CGPoint, wingWidth: CGFloat, excludingMediaControls: Bool) -> Bool {
        guard shouldOpen(at: point, wingWidth: wingWidth) else { return false }
        guard excludingMediaControls else { return true }
        return mediaControlAction(at: point, wingWidth: wingWidth) == nil
    }

    func clickRoute(at point: CGPoint, wingWidth: CGFloat, mediaControlsActive: Bool) -> CompactClickRoute {
        if mediaControlsActive, let action = mediaControlAction(at: point, wingWidth: wingWidth) {
            return .mediaControl(action)
        }
        return collapsedRect.contains(point) ? .openPanel : .passThrough
    }
}
