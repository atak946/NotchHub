import AppKit
import ApplicationServices

/// One entry of another app's menu. Pressing it works while that menu is closed.
struct MenuBarMenuNode: @unchecked Sendable {
    let title: String
    let isEnabled: Bool
    let isChecked: Bool
    let isSeparator: Bool
    let children: [MenuBarMenuNode]
    /// AXUIElement is an immutable reference that is safe to message from any thread.
    let element: AXUIElement
}

/// Reads an icon's menu through Accessibility, without opening it.
enum MenuBarMenuReader {
    private static let maxDepth = 4
    private static let markAttribute = "AXMenuItemMarkChar"

    /// `nil` when there is no menu or part of it cannot be copied (custom views have no title).
    static func read(_ item: MenuBarItem) async -> [MenuBarMenuNode]? {
        guard let menu = (AXAttributes.elements(of: item.element, kAXChildrenAttribute) ?? [])
            .first(where: { AXAttributes.string(of: $0, kAXRoleAttribute) == kAXMenuRole })
        else { return nil }
        guard let nodes = nodes(of: menu, depth: 0), nodes.contains(where: { !$0.isSeparator }) else { return nil }
        return nodes
    }

    private static func nodes(of menu: AXUIElement, depth: Int) -> [MenuBarMenuNode]? {
        guard depth < maxDepth else { return nil }
        var nodes: [MenuBarMenuNode] = []
        for element in AXAttributes.elements(of: menu, kAXChildrenAttribute) ?? [] {
            guard let node = node(element, depth: depth) else { return nil }
            nodes.append(node)
        }
        return nodes
    }

    private static func node(_ element: AXUIElement, depth: Int) -> MenuBarMenuNode? {
        let title = AXAttributes.string(of: element, kAXTitleAttribute) ?? ""
        let isEnabled = AXAttributes.value(of: element, kAXEnabledAttribute) as? Bool ?? false
        let submenu = AXAttributes.elements(of: element, kAXChildrenAttribute)?.first
        let isSeparator = title.isEmpty && !isEnabled && submenu == nil
        guard isSeparator || !title.isEmpty else { return nil }
        var children: [MenuBarMenuNode] = []
        if let submenu {
            guard let read = nodes(of: submenu, depth: depth + 1) else { return nil }
            children = read
        }
        return MenuBarMenuNode(
            title: title,
            isEnabled: isEnabled,
            isChecked: !(AXAttributes.string(of: element, markAttribute) ?? "").isEmpty,
            isSeparator: isSeparator,
            children: children,
            element: element
        )
    }
}

/// Shows the copy as a native menu and presses the original entry that was chosen.
@MainActor
final class MenuBarMenuCopy: NSObject {
    private final class Box {
        let element: AXUIElement
        init(_ element: AXUIElement) { self.element = element }
    }

    /// Blocks until the menu closes. `origin` is its top left corner in Cocoa coordinates.
    func show(_ nodes: [MenuBarMenuNode], at origin: CGPoint) {
        makeMenu(nodes).popUp(positioning: nil, at: origin, in: nil)
    }

    private func makeMenu(_ nodes: [MenuBarMenuNode]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for node in nodes {
            menu.addItem(node.isSeparator ? .separator() : makeItem(node))
        }
        return menu
    }

    private func makeItem(_ node: MenuBarMenuNode) -> NSMenuItem {
        let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
        item.isEnabled = node.isEnabled
        item.state = node.isChecked ? .on : .off
        if node.children.isEmpty {
            item.action = #selector(choose)
            item.target = self
            item.representedObject = Box(node.element)
        } else {
            item.submenu = makeMenu(node.children)
        }
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box else { return }
        MenuBarItemActivator.pressInBackground(box.element)
    }
}
