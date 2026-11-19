import CoreGraphics

/// Layout and hit-testing for the media controls in the right wing. They stay hidden until the pointer
/// reaches their rect, so the wing keeps showing status glyphs the rest of the time.
extension NotchGeometry {
    /// Wing width while the controls are available: the three buttons, or the mic button plus them.
    static let mediaControlsWingWidth: CGFloat = 104
    static let mediaControlButtonWidth: CGFloat = 24
    static let mediaControlsBoxHeight: CGFloat = 22
    /// Gap between the notch's right edge and the controls box.
    static let mediaControlsNotchInset: CGFloat = 4
    /// Gap between the meeting mic button and the controls when both show.
    static let mediaControlsMicGap: CGFloat = 6
    /// Extends hit areas above the screen so the very top pixel row counts, like the hot zone.
    private static let topEdgeAllowance: CGFloat = 1

    static var mediaControlsWidth: CGFloat {
        mediaControlButtonWidth * CGFloat(MediaControlAction.allCases.count)
    }

    /// Distance from the notch's right edge to the controls; they sit after the mic button when it shows.
    static func mediaControlsLeadingInset(afterMicMute: Bool) -> CGFloat {
        guard afterMicMute else { return mediaControlsNotchInset }
        return micMuteNotchInset + micMuteButtonWidth + mediaControlsMicGap
    }

    /// The controls box in screen coordinates, full notch height; nil when the wing is too narrow.
    func mediaControlsRect(wingWidth: CGFloat, afterMicMute: Bool = false) -> CGRect? {
        let width = Self.mediaControlsWidth
        let inset = Self.mediaControlsLeadingInset(afterMicMute: afterMicMute)
        guard wingWidth >= width + inset else { return nil }
        let collapsed = collapsedRect(wingWidth: wingWidth)
        let notchMaxX = collapsed.maxX - wingWidth
        return CGRect(x: notchMaxX + inset, y: collapsed.minY, width: width, height: collapsed.height)
    }

    /// Where the pointer reveals the controls: their rect plus the top pixel row.
    func mediaControlsRevealRect(wingWidth: CGFloat, afterMicMute: Bool = false) -> CGRect? {
        mediaControlsRect(wingWidth: wingWidth, afterMicMute: afterMicMute).map {
            CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height + Self.topEdgeAllowance)
        }
    }

    /// One contiguous hit rect per button, left to right.
    func mediaControlRects(
        wingWidth: CGFloat, afterMicMute: Bool = false
    ) -> [(action: MediaControlAction, rect: CGRect)] {
        guard let box = mediaControlsRevealRect(wingWidth: wingWidth, afterMicMute: afterMicMute) else { return [] }
        let buttonWidth = Self.mediaControlButtonWidth
        return MediaControlAction.allCases.enumerated().map { index, action in
            let rect = CGRect(
                x: box.minX + CGFloat(index) * buttonWidth, y: box.minY, width: buttonWidth, height: box.height
            )
            return (action, rect)
        }
    }

    func mediaControlAction(at point: CGPoint, wingWidth: CGFloat, afterMicMute: Bool = false) -> MediaControlAction? {
        mediaControlRects(wingWidth: wingWidth, afterMicMute: afterMicMute).first { $0.rect.contains(point) }?.action
    }

    /// Hover-to-open trigger; the controls area never starts the open timer while it is interactive.
    func shouldOpen(
        at point: CGPoint, wingWidth: CGFloat, excludingMediaControls: Bool, afterMicMute: Bool = false
    ) -> Bool {
        guard shouldOpen(at: point, wingWidth: wingWidth) else { return false }
        guard excludingMediaControls else { return true }
        return mediaControlAction(at: point, wingWidth: wingWidth, afterMicMute: afterMicMute) == nil
    }

    func clickRoute(
        at point: CGPoint, wingWidth: CGFloat, mediaControlsActive: Bool, afterMicMute: Bool = false
    ) -> CompactClickRoute {
        if mediaControlsActive,
           let action = mediaControlAction(at: point, wingWidth: wingWidth, afterMicMute: afterMicMute) {
            return .mediaControl(action)
        }
        return collapsedRect.contains(point) ? .openPanel : .passThrough
    }
}
