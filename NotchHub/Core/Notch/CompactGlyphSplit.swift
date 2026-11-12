import CoreGraphics

/// Decides which status glyphs go beside the closed notch. Glyphs are in priority order:
/// the right wing takes as many as fit, an empty left wing (no media) takes the next ones,
/// and whatever is left is counted in a "+N" pill at the end of the last wing in use.
enum CompactGlyphSplit {
    struct Result: Equatable, Sendable {
        /// Glyphs `0..<right` sit in the right wing.
        let right: Int
        /// Glyphs `right..<right + left` sit in the left wing.
        let left: Int
        /// Glyphs folded into the pill.
        let overflow: Int

        /// The pill goes to the left wing whenever that wing is available.
        let pillInLeftWing: Bool
    }

    static let spacing: CGFloat = 4
    /// Fixed so the split can reserve room for it before it is drawn.
    static let pillWidth: CGFloat = 22

    /// `widths` are the glyphs' natural widths; `nil` means not measured yet and counts as zero.
    static func split(widths: [CGFloat?], rightWidth: CGFloat, leftWidth: CGFloat) -> Result {
        let sizes = widths.map { $0 ?? 0 }
        var right = fittingCount(sizes, from: 0, in: rightWidth)
        var left = leftWidth > 0 ? fittingCount(sizes, from: right, in: leftWidth) : 0
        guard right + left < sizes.count else {
            return Result(right: right, left: left, overflow: 0, pillInLeftWing: false)
        }
        // Not everything fits: reserve the pill's room in the last wing and fit again.
        let pillRoom = pillWidth + spacing
        let usesLeftWing = leftWidth > 0
        if usesLeftWing {
            left = fittingCount(sizes, from: right, in: leftWidth - pillRoom)
        } else {
            right = fittingCount(sizes, from: 0, in: rightWidth - pillRoom)
        }
        return Result(right: right, left: left, overflow: sizes.count - right - left, pillInLeftWing: usesLeftWing)
    }

    /// How many glyphs from `start` fit in `width`, in order; stops at the first one that does not fit.
    private static func fittingCount(_ sizes: [CGFloat], from start: Int, in width: CGFloat) -> Int {
        var used: CGFloat = 0
        var count = 0
        for size in sizes.dropFirst(start) {
            let next = used + (count == 0 ? 0 : spacing) + size
            guard next <= width else { break }
            used = next
            count += 1
        }
        return count
    }
}
