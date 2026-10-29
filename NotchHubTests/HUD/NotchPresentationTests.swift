import CoreGraphics
import Testing
@testable import NotchHub

struct NotchPresentationTests {
    private let geometry = NotchGeometry.make(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 38,
        leftAuxiliaryWidth: 660,
        rightAuxiliaryWidth: 660,
        menuBarHeight: 38
    )

    private func resolve(mirror: Bool = false, expanded: Bool = false, alert: Bool = false, hud: Bool = false) -> NotchPresentation {
        .resolve(isCameraMirrorShown: mirror, isExpanded: expanded, hasAlert: alert, hasHUD: hud)
    }

    @Test func idleIsCollapsed() {
        #expect(resolve() == .collapsed)
    }

    @Test func hudShowsOnlyOverTheCollapsedNotch() {
        #expect(resolve(hud: true) == .hud)
        #expect(resolve(alert: true, hud: true) == .alert)
        #expect(resolve(expanded: true, hud: true) == .expanded)
    }

    @Test func expandedPanelBeatsAlerts() {
        #expect(resolve(expanded: true, alert: true) == .expanded)
    }

    @Test func cameraMirrorBeatsEverything() {
        #expect(resolve(mirror: true, expanded: true, alert: true, hud: true) == .cameraMirror)
    }

    @Test func hudAndCollapsedNeverTakeClicks() {
        #expect(NotchPresentation.hud.interactiveRect(in: geometry) == nil)
        #expect(NotchPresentation.collapsed.interactiveRect(in: geometry) == nil)
    }

    @Test func interactiveRectsMatchTheVisibleShape() {
        #expect(NotchPresentation.expanded.interactiveRect(in: geometry) == geometry.expandedRect)
        #expect(NotchPresentation.alert.interactiveRect(in: geometry) == geometry.alertRect)
        #expect(NotchPresentation.cameraMirror.interactiveRect(in: geometry) == geometry.cameraMirrorRect)
    }

    @Test func overlaysHangFromTheTopCenterAndFitThePanel() {
        for rect in [geometry.hudRect, geometry.cameraMirrorRect] {
            #expect(rect.midX == geometry.screenFrame.midX)
            #expect(rect.maxY == geometry.screenFrame.maxY)
            #expect(geometry.expandedRect.contains(rect))
        }
        #expect(geometry.hudRect.height == geometry.notchSize.height + NotchGeometry.hudStripHeight)
        #expect(geometry.cameraMirrorRect.width >= NotchGeometry.cameraMirrorPreviewSize.width)
    }
}
