import CoreGraphics

/// Pure layout math for the notch panel, in AppKit screen coordinates (origin bottom-left).
struct NotchGeometry: Equatable, Sendable {
    static let expandedSize = CGSize(width: 760, height: 230)
    static let compactWingWidth: CGFloat = 40
    static let wideCompactWingWidth: CGFloat = 84
    /// Area below the notch band: a 46pt content row, a 2pt gap and room for the countdown line.
    static let alertContentSize = CGSize(width: 480, height: 64)
    static let minimumAlertPadding: CGFloat = 160
    static let virtualNotchSize = CGSize(width: 190, height: 32)
    static let hotZonePadding = CGSize(width: 16, height: 6)
    static let exitTolerance: CGFloat = 12
    static let shadowMargin: CGFloat = 28
    static let minimumExpandedPadding: CGFloat = 80

    let screenFrame: CGRect
    let notchSize: CGSize
    let hasPhysicalNotch: Bool

    static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        leftAuxiliaryWidth: CGFloat?,
        rightAuxiliaryWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = leftAuxiliaryWidth, let right = rightAuxiliaryWidth {
            let width = screenFrame.width - left - right
            if width > 0 {
                return NotchGeometry(
                    screenFrame: screenFrame,
                    notchSize: CGSize(width: width, height: safeAreaTop),
                    hasPhysicalNotch: true
                )
            }
        }
        let height = menuBarHeight > 0 ? menuBarHeight : virtualNotchSize.height
        return NotchGeometry(
            screenFrame: screenFrame,
            notchSize: CGSize(width: virtualNotchSize.width, height: height),
            hasPhysicalNotch: false
        )
    }

    var collapsedRect: CGRect {
        collapsedRect(wingWidth: 0)
    }

    /// Collapsed notch plus optional compact "wings" on both sides for live indicators.
    func collapsedRect(wingWidth: CGFloat) -> CGRect {
        topCenteredRect(size: CGSize(width: notchSize.width + wingWidth * 2, height: notchSize.height))
    }

    var expandedRect: CGRect {
        let width = max(Self.expandedSize.width, notchSize.width + Self.minimumExpandedPadding)
        let height = max(Self.expandedSize.height, notchSize.height * 3)
        return topCenteredRect(size: CGSize(width: width, height: height))
    }

    /// Banner that grows out of the notch for alerts; always fits inside the panel.
    var alertRect: CGRect {
        let width = min(
            max(Self.alertContentSize.width, notchSize.width + Self.minimumAlertPadding),
            expandedRect.width
        )
        return topCenteredRect(size: CGSize(width: width, height: notchSize.height + Self.alertContentSize.height))
    }

    /// The window frame: expanded area plus room for the drop shadow on the sides and bottom.
    var panelRect: CGRect {
        let expanded = expandedRect
        let margin = Self.shadowMargin
        return CGRect(
            x: expanded.minX - margin,
            y: expanded.minY - margin,
            width: expanded.width + margin * 2,
            height: expanded.height + margin
        )
    }

    /// Area that opens the panel on hover. Extends one point above the screen so the top edge counts.
    var hotZone: CGRect {
        hotZone(wingWidth: 0)
    }

    func hotZone(wingWidth: CGFloat) -> CGRect {
        let collapsed = collapsedRect(wingWidth: wingWidth)
        let padding = Self.hotZonePadding
        return CGRect(
            x: collapsed.minX - padding.width,
            y: collapsed.minY - padding.height,
            width: collapsed.width + padding.width * 2,
            height: collapsed.height + padding.height + 1
        )
    }

    func shouldOpen(at point: CGPoint, wingWidth: CGFloat = 0) -> Bool {
        hotZone(wingWidth: wingWidth).contains(point)
    }

    func shouldClose(at point: CGPoint) -> Bool {
        let tolerance = Self.exitTolerance
        let area = expandedRect.insetBy(dx: -tolerance, dy: -tolerance)
        return !area.contains(point)
    }

    private func topCenteredRect(size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
