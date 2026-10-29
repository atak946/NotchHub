import CoreGraphics
import Testing
@testable import NotchHub

struct NotchGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func physical() -> NotchGeometry {
        NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 38,
            leftAuxiliaryWidth: 660,
            rightAuxiliaryWidth: 660,
            menuBarHeight: 38
        )
    }

    @Test func detectsPhysicalNotchFromAuxiliaryAreas() {
        let geometry = physical()

        #expect(geometry.hasPhysicalNotch)
        #expect(geometry.notchSize == CGSize(width: 192, height: 38))
    }

    @Test func fallsBackToVirtualNotchWithoutSafeArea() {
        let geometry = NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 0,
            leftAuxiliaryWidth: nil,
            rightAuxiliaryWidth: nil,
            menuBarHeight: 25
        )

        #expect(!geometry.hasPhysicalNotch)
        #expect(geometry.notchSize == CGSize(width: NotchGeometry.virtualNotchSize.width, height: 25))
    }

    @Test func usesDefaultHeightWhenMenuBarIsHidden() {
        let geometry = NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 0,
            leftAuxiliaryWidth: nil,
            rightAuxiliaryWidth: nil,
            menuBarHeight: 0
        )

        #expect(geometry.notchSize.height == NotchGeometry.virtualNotchSize.height)
    }

    @Test func collapsedRectIsTopCentered() {
        let rect = physical().collapsedRect

        #expect(rect.midX == screen.midX)
        #expect(rect.maxY == screen.maxY)
    }

    @Test func centersOnSecondaryScreenWithOffsetOrigin() {
        let external = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let geometry = NotchGeometry.make(
            screenFrame: external,
            safeAreaTop: 0,
            leftAuxiliaryWidth: nil,
            rightAuxiliaryWidth: nil,
            menuBarHeight: 25
        )

        #expect(geometry.expandedRect.midX == external.midX)
        #expect(geometry.expandedRect.maxY == external.maxY)
    }

    @Test func panelContainsExpandedRectWithShadowMargin() {
        let geometry = physical()
        let panel = geometry.panelRect

        #expect(panel.contains(geometry.expandedRect))
        #expect(panel.maxY == screen.maxY)
        #expect(panel.minY == geometry.expandedRect.minY - NotchGeometry.shadowMargin)
    }

    @Test func opensWhenPointerTouchesTopEdgeOfNotch() {
        let geometry = physical()

        #expect(geometry.shouldOpen(at: CGPoint(x: screen.midX, y: screen.maxY)))
        #expect(geometry.shouldOpen(at: CGPoint(x: screen.midX, y: screen.maxY - 20)))
    }

    @Test func doesNotOpenAwayFromNotch() {
        let geometry = physical()

        #expect(!geometry.shouldOpen(at: CGPoint(x: 100, y: screen.maxY)))
        #expect(!geometry.shouldOpen(at: CGPoint(x: screen.midX, y: screen.midY)))
    }

    @Test func staysOpenInsideExpandedAreaAndTolerance() {
        let geometry = physical()
        let expanded = geometry.expandedRect

        #expect(!geometry.shouldClose(at: CGPoint(x: expanded.midX, y: expanded.midY)))
        #expect(!geometry.shouldClose(at: CGPoint(x: expanded.minX - 5, y: expanded.midY)))
        #expect(geometry.shouldClose(at: CGPoint(x: expanded.midX, y: expanded.minY - 40)))
    }

    @Test func alertHangsFromNotchWithContentBand() {
        let geometry = physical()
        let alert = geometry.alertRect

        #expect(alert.width == NotchGeometry.alertContentSize.width)
        #expect(alert.height == geometry.notchSize.height + NotchGeometry.alertContentSize.height)
        #expect(alert.maxY == screen.maxY)
        #expect(alert.midX == screen.midX)
    }

    @Test func alertLeavesRoomBesideTheNotchForLabels() {
        let geometry = physical()
        let wing = (geometry.alertRect.width - geometry.notchSize.width) / 2

        #expect(wing >= NotchGeometry.minimumAlertPadding / 2)
    }

    @Test func alertWidensForWideNotchesButFitsThePanel() {
        let geometry = NotchGeometry(
            screenFrame: screen,
            notchSize: CGSize(width: 420, height: 38),
            hasPhysicalNotch: true
        )

        #expect(geometry.alertRect.width == 420 + NotchGeometry.minimumAlertPadding)
        #expect(geometry.alertRect.width <= geometry.expandedRect.width)
        #expect(geometry.panelRect.contains(geometry.alertRect))
    }
}

struct FullScreenMatcherTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func matchesWindowCoveringDisplay() {
        #expect(FullScreenMatcher.covers(display, display: display))
        #expect(FullScreenMatcher.covers(display.insetBy(dx: 0.5, dy: 0.5), display: display))
    }

    @Test func rejectsMaximizedWindowBelowMenuBar() {
        let window = CGRect(x: 0, y: 38, width: 1512, height: 944)

        #expect(!FullScreenMatcher.covers(window, display: display))
    }
}
