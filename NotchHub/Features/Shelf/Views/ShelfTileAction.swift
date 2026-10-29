import AppKit

/// A quick action shown as a hover button and in the context menu.
struct ShelfTileAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let perform: @MainActor () -> Void

    init(id: String, title: String, systemImage: String, isDestructive: Bool = false, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.perform = perform
    }

    @MainActor
    static func menu(primary: [ShelfTileAction], secondary: [ShelfTileAction]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        primary.forEach { menu.addItem($0.menuItem) }
        if !primary.isEmpty, !secondary.isEmpty { menu.addItem(.separator()) }
        secondary.forEach { menu.addItem($0.menuItem) }
        return menu
    }

    @MainActor
    private var menuItem: NSMenuItem {
        ShelfMenuItem(title: title, systemImage: systemImage, handler: perform)
    }
}
