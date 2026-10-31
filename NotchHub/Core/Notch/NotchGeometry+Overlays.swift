import CoreGraphics

/// Rects of the small overlays that grow out of the collapsed notch: the level HUD and the camera mirror.
extension NotchGeometry {
    /// The level HUD is a capsule ("island") floating just under the notch: icon, bar and value in one row.
    static let hudPillSize = CGSize(width: 232, height: 32)
    /// Gap between the notch's bottom edge and the HUD capsule.
    static let hudPillGap: CGFloat = 6
    static let cameraMirrorPreviewSize = CGSize(width: 240, height: 135)
    /// Gap between the notch band and the preview.
    static let cameraMirrorTopGap: CGFloat = 6
    /// Black margin around the preview on the sides and bottom.
    static let cameraMirrorPadding: CGFloat = 14
    /// Minimum black margin beside the hardware notch so the shape still reads as a notch.
    static let cameraMirrorMinimumWing: CGFloat = 24

    /// The notch band plus the capsule hanging under it; scrolling anywhere in here adjusts the level.
    var hudRect: CGRect {
        let width = min(max(notchSize.width, Self.hudPillSize.width), expandedRect.width)
        return overlayRect(size: CGSize(width: width, height: notchSize.height + Self.hudPillGap + Self.hudPillSize.height))
    }

    /// The capsule itself; the only part of the HUD that takes clicks, so the menu bar beside the notch stays
    /// click-through.
    var hudBarRect: CGRect {
        let hud = hudRect
        let width = min(Self.hudPillSize.width, hud.width)
        return CGRect(x: hud.midX - width / 2, y: hud.minY, width: width, height: Self.hudPillSize.height)
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
