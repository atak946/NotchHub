import Foundation
import Testing
@testable import NotchHub

struct ShelfSelectionTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test func plainClickSelectsSingleItem() {
        var selection = ShelfSelection()
        selection.press(a, toggling: false)
        selection.release(a, toggling: false, didDrag: false)
        selection.press(b, toggling: false)

        #expect(selection.ids == [b])
    }

    @Test func commandClickToggles() {
        var selection = ShelfSelection()
        selection.press(a, toggling: false)
        selection.press(b, toggling: true)
        #expect(selection.ids == [a, b])

        selection.press(a, toggling: true)
        #expect(selection.ids == [b])
    }

    @Test func pressingSelectedItemKeepsGroupForDrag() {
        var selection = ShelfSelection()
        selection.press(a, toggling: false)
        selection.press(c, toggling: true)

        selection.press(c, toggling: false)
        selection.release(c, toggling: false, didDrag: true)

        #expect(selection.ids == [a, c])
        #expect(selection.targetIDs(for: c, orderedBy: [a, b, c]) == [a, c])
    }

    @Test func clickWithoutDragNarrowsGroup() {
        var selection = ShelfSelection()
        selection.press(a, toggling: false)
        selection.press(b, toggling: true)

        selection.press(b, toggling: false)
        selection.release(b, toggling: false, didDrag: false)

        #expect(selection.ids == [b])
    }

    @Test func targetsUnselectedItemAlone() {
        var selection = ShelfSelection()
        selection.press(a, toggling: false)

        #expect(selection.targetIDs(for: b, orderedBy: [a, b]) == [b])
    }

    @Test func pruneDropsRemovedItems() {
        var selection = ShelfSelection()
        selection.press(a, toggling: false)
        selection.press(b, toggling: true)

        selection.prune(keeping: [b, c])
        #expect(selection.ids == [b])

        selection.clear()
        #expect(selection.isEmpty)
    }
}
