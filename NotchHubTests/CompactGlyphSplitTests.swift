import CoreGraphics
import Testing
@testable import NotchHub

struct CompactGlyphSplitTests {
    private let spacing = CompactGlyphSplit.spacing
    private let pill = CompactGlyphSplit.pillWidth

    @Test func everythingFitsInTheRightWing() {
        let result = CompactGlyphSplit.split(widths: [22, 40], rightWidth: 84, leftWidth: 0)
        #expect(result == .init(right: 2, left: 0, overflow: 0, pillInLeftWing: false))
    }

    @Test func overflowMovesToAFreeLeftWing() {
        let result = CompactGlyphSplit.split(widths: [40, 30, 14], rightWidth: 80, leftWidth: 84)
        #expect(result == .init(right: 2, left: 1, overflow: 0, pillInLeftWing: false))
    }

    @Test func withoutALeftWingTheRestFoldsIntoAPillOnTheRight() {
        // 40 + 4 + 14 + 4 + pill (22) = 84 fits; the third glyph does not.
        let result = CompactGlyphSplit.split(widths: [40, 14, 30], rightWidth: 84, leftWidth: 0)
        #expect(result == .init(right: 2, left: 0, overflow: 1, pillInLeftWing: false))
    }

    @Test func pillReservesRoomInTheLeftWingWhenBothWingsAreFull() {
        let result = CompactGlyphSplit.split(widths: [40, 40, 40, 40, 40], rightWidth: 84, leftWidth: 84)
        // Right: 40 + 4 + 40 = 84. Left keeps 26 pt for the pill: one 40 fits in 58, two do not.
        #expect(result == .init(right: 2, left: 1, overflow: 2, pillInLeftWing: true))
    }

    @Test func keepsPriorityOrderInsteadOfSkippingAWideGlyph() {
        // 70 + pill fits in 100; the 5 pt glyph after the 40 pt one is not pulled forward.
        let result = CompactGlyphSplit.split(widths: [70, 40, 5], rightWidth: 100, leftWidth: 0)
        #expect(result.right == 1)
        #expect(result.overflow == 2)
    }

    @Test func unmeasuredGlyphsCountAsFitting() {
        let result = CompactGlyphSplit.split(widths: [nil, nil], rightWidth: 10, leftWidth: 0)
        #expect(result == .init(right: 2, left: 0, overflow: 0, pillInLeftWing: false))
    }

    @Test func onlyThePillWhenNothingFits() {
        let result = CompactGlyphSplit.split(widths: [100], rightWidth: 30, leftWidth: 0)
        #expect(result == .init(right: 0, left: 0, overflow: 1, pillInLeftWing: false))
    }

    @Test func pillScreenRectFlipsTheVerticalAxis() {
        let panel = CGRect(x: 500, y: 700, width: 800, height: 300)
        let pillInView = CGRect(x: 600, y: 10, width: 22, height: 12)

        let rect = NotchGeometry.screenRect(ofViewRect: pillInView, inPanelFrame: panel)

        #expect(rect == CGRect(x: 1100, y: 978, width: 22, height: 12))
        #expect(NotchGeometry.isOnOverflowPill(CGPoint(x: 1110, y: 984), pillFrame: pillInView, panelFrame: panel))
        #expect(!NotchGeometry.isOnOverflowPill(CGPoint(x: 1000, y: 984), pillFrame: pillInView, panelFrame: panel))
        #expect(!NotchGeometry.isOnOverflowPill(CGPoint(x: 1110, y: 984), pillFrame: nil, panelFrame: panel))
    }
}
