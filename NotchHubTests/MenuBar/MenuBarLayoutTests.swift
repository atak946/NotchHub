import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import NotchHub

struct MenuBarLayoutTests {
    private let screens = [CGRect(x: 0, y: 0, width: 2056, height: 1329), CGRect(x: -1920, y: 249, width: 1920, height: 1080)]

    private func item(_ id: String, x: CGFloat, y: CGFloat = 252, width: CGFloat = 24) -> MenuBarItem {
        MenuBarItem(
            id: id, pid: 1, bundleID: nil, name: id, value: nil, identifier: nil,
            frame: CGRect(x: x, y: y, width: width, height: 24), element: AXUIElementCreateSystemWide()
        )
    }

    @Test func hiddenItemsAreLeftOfTheDividerOnItsBar() {
        let divider = CGRect(x: -5262, y: 249, width: 5016, height: 30)
        let items = [
            item("visible", x: -238), item("second", x: -5511), item("first", x: -5589),
            item("other bar", x: -6000, y: 2), item("not placed", x: 7, y: 1328),
        ]
        #expect(MenuBarLayout.hiddenItems(in: items, divider: divider).map(\.id) == ["first", "second"])
    }

    @Test func chevronMustBeRightOfTheDivider() {
        let left = CGRect(x: 100, y: 0, width: 20, height: 30)
        let right = CGRect(x: 130, y: 0, width: 20, height: 30)
        #expect(MenuBarLayout.canHide(chevron: right, divider: left))
        #expect(!MenuBarLayout.canHide(chevron: left, divider: right))
    }

    @Test func onScreenNeedsAWholeIconOnAMenuBar() {
        #expect(MenuBarLayout.isOnScreen(CGRect(x: -573, y: 252, width: 26, height: 24), screens: screens))
        #expect(!MenuBarLayout.isOnScreen(CGRect(x: -5589, y: 252, width: 26, height: 24), screens: screens))
        #expect(!MenuBarLayout.isOnScreen(CGRect(x: 7, y: 1328, width: 24, height: 24), screens: screens))
        #expect(!MenuBarLayout.isOnScreen(.zero, screens: screens))
    }

    @Test func newItemsGoLeftOfTheSystemIcons() {
        let system = [CGRect(x: -126, y: 253, width: 118, height: 22), CGRect(x: -238, y: 253, width: 16, height: 22)]
        #expect(MenuBarLayout.preferredPosition(systemItems: system, screens: screens) == 238)
        #expect(MenuBarLayout.preferredPosition(systemItems: [], screens: screens) == nil)
    }

    @Test func hostWindowSharesTheIconsCenter() {
        let window = MenuBarHostWindow(id: 1, ownerPID: 1, frame: CGRect(x: -5364, y: 249, width: 64, height: 30), name: nil)
        #expect(window.hosts(CGRect(x: -5365, y: 252, width: 66, height: 24)))
        #expect(!window.hosts(CGRect(x: -5325, y: 252, width: 56, height: 24)))
        #expect(!window.hosts(CGRect(x: -5365, y: 2, width: 66, height: 24)))
    }
}

struct MenuBarStrategyStoreTests {
    @Test func keepsButtonsApartAndPersists() {
        let defaults = TestDefaults.suite(named: "MenuBarStrategy.\(UUID().uuidString)")
        var store = MenuBarStrategyStore(defaults: defaults)
        store["app", .left] = .copyMenu
        store["app", .right] = .reveal

        let reloaded = MenuBarStrategyStore(defaults: defaults)
        #expect(reloaded["app", .left] == .copyMenu)
        #expect(reloaded["app", .right] == .reveal)
        #expect(reloaded["other", .left] == nil)
    }

    @Test func ignoresUnknownAndMissingApps() {
        let defaults = TestDefaults.suite(named: "MenuBarStrategy.\(UUID().uuidString)")
        defaults.set(["app": "moveWindow"], forKey: "MenuBarContainer.strategies")
        var store = MenuBarStrategyStore(defaults: defaults)
        #expect(store["app", .left] == nil)
        store[nil, .left] = .reveal
        #expect(store[nil, .left] == nil)
    }
}

@MainActor
struct MenuBarContainerTests {
    @Test func everythingIsOffByDefault() {
        let defaults = TestDefaults.suite(named: "MenuBarContainer.\(UUID().uuidString)")
        let container = MenuBarContainer(permission: AccessibilityPermission(), defaults: defaults)
        #expect(!container.isEnabled)
        #expect(!container.showsLiveIcons)
        #expect(container.items.isEmpty)
    }
}
