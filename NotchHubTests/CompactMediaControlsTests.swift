import CoreGraphics
import Foundation
import Testing
@testable import NotchHub

struct CompactMediaControlsGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let wing = NotchGeometry.mediaControlsWingWidth

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

    private func virtual(on frame: CGRect) -> NotchGeometry {
        NotchGeometry.make(
            screenFrame: frame,
            safeAreaTop: 0,
            leftAuxiliaryWidth: nil,
            rightAuxiliaryWidth: nil,
            menuBarHeight: 25
        )
    }

    @Test func controlsBoxSitsAtInnerEndOfRightWing() throws {
        let rect = try #require(physical().mediaControlsRect(wingWidth: wing))

        #expect(rect == CGRect(x: 856, y: 944, width: 72, height: 38))
        #expect(rect.minX == 852 + NotchGeometry.mediaControlsNotchInset)
        #expect(physical().collapsedRect(wingWidth: wing).contains(CGPoint(x: rect.midX, y: rect.midY)))
    }

    @Test func controlsFitInsideWingWithRoomForGlyphs() {
        let glyphRoom: CGFloat = 24
        #expect(
            NotchGeometry.mediaControlsWingWidth
                >= NotchGeometry.mediaControlsWidth + NotchGeometry.mediaControlsNotchInset + glyphRoom
        )
        #expect(NotchGeometry.mediaControlsWingWidth > NotchGeometry.wideCompactWingWidth)
    }

    @Test func noControlsWhenWingIsTooNarrow() {
        let geometry = physical()

        #expect(geometry.mediaControlsRect(wingWidth: NotchGeometry.compactWingWidth) == nil)
        #expect(geometry.mediaControlRects(wingWidth: 0).isEmpty)
    }

    @Test func revealRectCoversControlsAndTopPixelRow() throws {
        let geometry = physical()
        let box = try #require(geometry.mediaControlsRect(wingWidth: wing))
        let reveal = try #require(geometry.mediaControlsRevealRect(wingWidth: wing))
        #expect(reveal.contains(CGPoint(x: box.midX, y: 982)))
        #expect(reveal.minX == box.minX && reveal.width == box.width)
        #expect(!reveal.contains(CGPoint(x: box.maxX + 2, y: 960)))
    }

    @Test func buttonRectsAreContiguousAndWideEnough() {
        let rects = physical().mediaControlRects(wingWidth: wing)

        #expect(rects.map(\.action) == [.previous, .playPause, .next])
        for (index, entry) in rects.enumerated() {
            #expect(entry.rect.width >= 22)
            if index > 0 {
                #expect(entry.rect.minX == rects[index - 1].rect.maxX)
            }
        }
    }

    @Test func mapsPointsToActions() {
        let geometry = physical()

        #expect(geometry.mediaControlAction(at: CGPoint(x: 862, y: 960), wingWidth: wing) == .previous)
        #expect(geometry.mediaControlAction(at: CGPoint(x: 892, y: 960), wingWidth: wing) == .playPause)
        #expect(geometry.mediaControlAction(at: CGPoint(x: 922, y: 960), wingWidth: wing) == .next)
        // Very top pixel row still counts.
        #expect(geometry.mediaControlAction(at: CGPoint(x: 892, y: 982), wingWidth: wing) == .playPause)
        // Glyph area, notch gap and below the menu bar are not controls.
        #expect(geometry.mediaControlAction(at: CGPoint(x: 940, y: 960), wingWidth: wing) == nil)
        #expect(geometry.mediaControlAction(at: CGPoint(x: 854, y: 960), wingWidth: wing) == nil)
        #expect(geometry.mediaControlAction(at: CGPoint(x: 892, y: 940), wingWidth: wing) == nil)
    }

    @Test func hoverOverControlsDoesNotTriggerOpen() {
        let geometry = physical()
        let onControl = CGPoint(x: 892, y: 960)
        let onNotch = CGPoint(x: 756, y: 970)
        let onGlyphs = CGPoint(x: 940, y: 960)

        #expect(!geometry.shouldOpen(at: onControl, wingWidth: wing, excludingMediaControls: true))
        #expect(geometry.shouldOpen(at: onNotch, wingWidth: wing, excludingMediaControls: true))
        #expect(geometry.shouldOpen(at: onGlyphs, wingWidth: wing, excludingMediaControls: true))
        // Exclusion off (setting off, alert, expanded): behaves like the plain hot zone.
        #expect(geometry.shouldOpen(at: onControl, wingWidth: wing, excludingMediaControls: false))
    }

    @Test func routesClicks() {
        let geometry = physical()

        #expect(geometry.clickRoute(at: CGPoint(x: 862, y: 960), wingWidth: wing, mediaControlsActive: true)
            == .mediaControl(.previous))
        #expect(geometry.clickRoute(at: CGPoint(x: 922, y: 960), wingWidth: wing, mediaControlsActive: true)
            == .mediaControl(.next))
        #expect(geometry.clickRoute(at: CGPoint(x: 756, y: 970), wingWidth: wing, mediaControlsActive: true)
            == .openPanel)
        // Outside the controls and the notch: left to the menu bar.
        #expect(geometry.clickRoute(at: CGPoint(x: 940, y: 960), wingWidth: wing, mediaControlsActive: true)
            == .passThrough)
        #expect(geometry.clickRoute(at: CGPoint(x: 100, y: 970), wingWidth: wing, mediaControlsActive: true)
            == .passThrough)
        #expect(geometry.clickRoute(at: CGPoint(x: 892, y: 960), wingWidth: wing, mediaControlsActive: false)
            == .passThrough)
    }

    @Test func followsVirtualNotchOnSecondaryScreen() throws {
        let external = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let geometry = virtual(on: external)
        let rect = try #require(geometry.mediaControlsRect(wingWidth: wing))
        let notchMaxX = external.midX + NotchGeometry.virtualNotchSize.width / 2

        #expect(rect.minX == notchMaxX + NotchGeometry.mediaControlsNotchInset)
        #expect(rect.maxY == external.maxY)
        #expect(rect.height == 25)
        #expect(geometry.mediaControlAction(at: CGPoint(x: rect.midX, y: rect.midY), wingWidth: wing) == .playPause)
    }
}

struct CompactMediaControlsPolicyTests {
    @Test func availableOnlyWithSettingAndActiveTrack() {
        #expect(CompactMediaControls.isAvailable(isEnabled: true, hasActiveTrack: true))
        #expect(!CompactMediaControls.isAvailable(isEnabled: false, hasActiveTrack: true))
        #expect(!CompactMediaControls.isAvailable(isEnabled: true, hasActiveTrack: false))
    }

    @Test func hiddenWhileAlertShowsOrPanelIsOpen() {
        #expect(CompactMediaControls.isInteractive(isAvailable: true, isAlertShowing: false, isExpanded: false))
        #expect(!CompactMediaControls.isInteractive(isAvailable: true, isAlertShowing: true, isExpanded: false))
        #expect(!CompactMediaControls.isInteractive(isAvailable: true, isAlertShowing: false, isExpanded: true))
        #expect(!CompactMediaControls.isInteractive(isAvailable: false, isAlertShowing: false, isExpanded: false))
    }

    @Test func playPauseIconFollowsPlaybackState() {
        #expect(MediaControlAction.playPause.systemImage(isPlaying: true) == "pause.fill")
        #expect(MediaControlAction.playPause.systemImage(isPlaying: false) == "play.fill")
        #expect(MediaControlAction.previous.systemImage(isPlaying: true) == "backward.fill")
        #expect(MediaControlAction.next.systemImage(isPlaying: false) == "forward.fill")
        #expect(MediaControlAction.playPause.title(isPlaying: true) == "Duraklat")
    }
}

@MainActor
struct CompactMediaControlsSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let (suiteName, defaults) = TestDefaults.makeSuite("CompactMediaControls.\(UUID().uuidString)")
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func enabledByDefault() {
        #expect(SettingsStore(defaults: makeDefaults()).showsCompactMediaControls)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        SettingsStore(defaults: defaults).showsCompactMediaControls = false

        #expect(!SettingsStore(defaults: defaults).showsCompactMediaControls)
    }
}
