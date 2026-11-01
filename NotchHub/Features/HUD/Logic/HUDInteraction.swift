import Foundation

/// Pure math for scrolling over and dragging the visible HUD.
enum HUDInteractionMath {
    /// A trackpad swipe over this many points spans the whole bar.
    static let preciseScrollRange = 240.0
    /// One mouse-wheel notch moves one macOS volume step.
    static let lineScrollStep = 1.0 / Double(MediaKeyPolicy.coarseStepCount)

    /// Volume and brightness can be set; the keyboard backlight has no public API.
    static func isAdjustable(_ kind: HUDKind) -> Bool {
        kind != .keyboardBacklight
    }

    /// The level after a scroll. Moving up on the device raises it, with or without natural scrolling.
    static func scrolled(_ level: Double, deltaY: Double, isPrecise: Bool, isInverted: Bool) -> Double {
        let physical = isInverted ? -deltaY : deltaY
        let change = isPrecise ? physical / preciseScrollRange : physical * lineScrollStep
        return HUDLevel.clamped(level + change)
    }

    /// The level under the pointer on a bar `barWidth` wide that starts `inset` points in.
    static func level(atX x: Double, barWidth: Double, inset: Double) -> Double {
        guard barWidth > 0 else { return 0 }
        return HUDLevel.clamped((x - inset) / barWidth)
    }
}

/// The level bar's colour.
enum HUDAccent {
    /// The artwork's colour while a track plays; white when nothing plays or the tint is not ready yet.
    static func barTint(isPlaying: Bool, artworkTint: RGBColor?) -> RGBColor {
        guard isPlaying, let artworkTint else { return .white }
        return artworkTint
    }
}

/// When the bar bounces at an end: on arriving there, and on each later press against it, but not on every
/// drag or scroll update while the pointer keeps pushing.
enum HUDBouncePolicy {
    /// About the bounce's own length, so presses against the end replay it without restarting it mid-way.
    static let minimumInterval: Duration = .milliseconds(450)

    static func shouldBounce(
        edge: HUDLevelEdge?,
        previousEdge: HUDLevelEdge?,
        isDragging: Bool,
        sinceLastBounce: Duration?
    ) -> Bool {
        guard let edge else { return false }
        if edge != previousEdge { return true }
        guard !isDragging else { return false }
        guard let sinceLastBounce else { return true }
        return sinceLastBounce >= minimumInterval
    }
}
