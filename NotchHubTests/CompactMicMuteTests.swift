import CoreGraphics
import Testing
@testable import NotchHub

struct CompactMicMuteTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let wing = NotchGeometry.micMuteWingWidth

    /// Notch 192 × 38 centered: spans x 660...852.
    private func physical() -> NotchGeometry {
        NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 38,
            leftAuxiliaryWidth: 660,
            rightAuxiliaryWidth: 660,
            menuBarHeight: 38
        )
    }

    @Test func buttonSitsAtInnerEdgeOfRightWing() throws {
        let rect = try #require(physical().micMuteButtonRect(wingWidth: wing))
        #expect(rect == CGRect(x: 856, y: 944, width: NotchGeometry.micMuteButtonWidth, height: 38))
        #expect(rect.minX == 852 + NotchGeometry.micMuteNotchInset)
        #expect(physical().collapsedRect(wingWidth: wing).contains(CGPoint(x: rect.midX, y: rect.midY)))
    }

    @Test func hitTestCoversTopPixelRowButNotNotch() {
        let geometry = physical()
        #expect(geometry.isOnMicMuteButton(CGPoint(x: 860, y: 982), wingWidth: wing))
        #expect(geometry.isOnMicMuteButton(CGPoint(x: 870, y: 960), wingWidth: wing))
        #expect(!geometry.isOnMicMuteButton(CGPoint(x: 850, y: 960), wingWidth: wing))
        #expect(!geometry.isOnMicMuteButton(CGPoint(x: 880, y: 960), wingWidth: wing))
    }

    @Test func doesNotOverlapMediaControls() throws {
        let geometry = physical()
        let mic = try #require(geometry.micMuteButtonRect(wingWidth: wing))
        let media = try #require(geometry.mediaControlsRect(wingWidth: wing))
        #expect(!mic.intersects(media))
        #expect(!mic.intersects(geometry.collapsedRect))
        #expect(media.maxX <= geometry.collapsedRect.minX)
    }

    @Test func noButtonWhenWingTooNarrow() {
        #expect(physical().micMuteButtonRect(wingWidth: 0) == nil)
        #expect(physical().micMuteButtonRect(wingWidth: 20) == nil)
        #expect(!physical().isOnMicMuteButton(CGPoint(x: 860, y: 960), wingWidth: 0))
    }

    @Test func visibleOnlyInMeetingWithControllableDevice() {
        #expect(CompactMicMute.isAvailable(isInMeeting: true, isControlAvailable: true))
        #expect(!CompactMicMute.isAvailable(isInMeeting: false, isControlAvailable: true))
        #expect(!CompactMicMute.isAvailable(isInMeeting: true, isControlAvailable: false))
    }

    @Test func interactiveOnlyWhileCollapsedWithoutAlert() {
        #expect(CompactMicMute.isInteractive(isAvailable: true, isAlertShowing: false, isExpanded: false))
        #expect(!CompactMicMute.isInteractive(isAvailable: true, isAlertShowing: true, isExpanded: false))
        #expect(!CompactMicMute.isInteractive(isAvailable: true, isAlertShowing: false, isExpanded: true))
        #expect(!CompactMicMute.isInteractive(isAvailable: false, isAlertShowing: false, isExpanded: false))
    }

    @Test func wingWidensForButtonButNeverShrinks() {
        #expect(CompactMicMute.wingWidth(base: NotchGeometry.wideCompactWingWidth, isAvailable: true) == wing)
        #expect(CompactMicMute.wingWidth(base: 200, isAvailable: true) == 200)
        #expect(CompactMicMute.wingWidth(base: NotchGeometry.compactWingWidth, isAvailable: false)
            == NotchGeometry.compactWingWidth)
        #expect(wing >= NotchGeometry.mediaControlsWingWidth)
    }
}
