import CoreGraphics

/// Rects of the small overlays that grow out of the collapsed notch: the level HUD and the camera mirror.
extension NotchGeometry {
    /// Room on each side of the notch for the HUD icon and percentage.
    static let hudWingWidth: CGFloat = 76
    /// Slim strip below the notch band that holds the level bar.
    static let hudStripHeight: CGFloat = 14
    static let cameraMirrorPreviewSize = CGSize(width: 240, height: 135)
    /// Gap between the notch band and the preview.
    static let cameraMirrorTopGap: CGFloat = 6
    /// Black margin around the preview on the sides and bottom.
    static let cameraMirrorPadding: CGFloat = 14
    /// Minimum black margin beside the hardware notch so the shape still reads as a notch.
    static let cameraMirrorMinimumWing: CGFloat = 24

    var hudRect: CGRect {
        let width = min(notchSize.width + Self.hudWingWidth * 2, expandedRect.width)
        return overlayRect(size: CGSize(width: width, height: notchSize.height + Self.hudStripHeight))
    }

    var cameraMirrorRect: CGRect {
        let preview = Self.cameraMirrorPreviewSize
        let width = min(
            max(preview.width + Self.cameraMirrorPadding * 2, notchSize.width + Self.cameraMirrorMinimumWing * 2),
            expandedRect.width
        )
        let height = notchSize.height + Self.cameraMirrorTopGap + preview.height + Self.cameraMirrorPadding
        return overlayRect(size: CGSize(width: width, height: height))
    }

    private func overlayRect(size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
