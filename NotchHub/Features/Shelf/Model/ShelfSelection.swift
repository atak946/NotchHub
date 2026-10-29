import Foundation

/// Finder-like selection: click selects one, ⌘-click toggles, pressing a selected
/// item keeps the selection so it can be dragged as a group.
struct ShelfSelection: Equatable, Sendable {
    private(set) var ids: Set<ShelfItem.ID> = []

    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: ShelfItem.ID) -> Bool {
        ids.contains(id)
    }

    mutating func press(_ id: ShelfItem.ID, toggling: Bool) {
        if toggling {
            ids = ids.symmetricDifference([id])
        } else if !ids.contains(id) {
            ids = [id]
        }
    }

    /// A plain click (no drag) on a member of a multi-selection narrows it to that item.
    mutating func release(_ id: ShelfItem.ID, toggling: Bool, didDrag: Bool) {
        guard !toggling, !didDrag else { return }
        ids = [id]
    }

    mutating func select(_ id: ShelfItem.ID) {
        ids = [id]
    }

    mutating func clear() {
        ids = []
    }

    /// Drops ids that are no longer on the shelf.
    mutating func prune(keeping validIDs: Set<ShelfItem.ID>) {
        ids = ids.intersection(validIDs)
    }

    /// Items acted on when `id` is the pressed item: the whole selection if it contains `id`.
    func targetIDs(for id: ShelfItem.ID, orderedBy order: [ShelfItem.ID]) -> [ShelfItem.ID] {
        ids.contains(id) ? order.filter(ids.contains) : [id]
    }
}
