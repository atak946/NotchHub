import SwiftUI

/// Feeds `NotchHUDView` with the playing track's artwork tint, the edge bounce trigger and the drag callbacks.
struct NotchHUDHost: View {
    let hud: SystemHUD
    let media: MediaService
    let reading: HUDReading
    let layout: NotchHUDView.Layout
    var tints: ArtworkTintStore = .shared

    @State private var edgeHits = 0
    @State private var lastEdge: HUDLevelEdge?
    @State private var lastBounce: ContinuousClock.Instant?

    private var isPlaying: Bool {
        media.nowPlaying?.isPlaying == true
    }

    var body: some View {
        NotchHUDView(
            reading: reading,
            layout: layout,
            accent: HUDAccent.barTint(isPlaying: isPlaying, artworkTint: media.artwork.map { tints.tint(for: $0) }),
            edgeHits: edgeHits,
            interaction: interaction
        )
        .task(id: media.artwork.map(ObjectIdentifier.init)) {
            guard let image = media.artwork else { return }
            await tints.prepare(image)
        }
        // Every show counts, so a key press at 0 % or 100 % bounces even though the level did not move.
        .onChange(of: hud.center.showCount, initial: true) { bounceIfAtEdge() }
        .onDisappear { hud.setDragging(false) }
    }

    private func bounceIfAtEdge() {
        let edge = hud.center.current.flatMap(HUDLevel.edge(of:))
        let now = ContinuousClock.now
        defer { lastEdge = edge }
        guard HUDBouncePolicy.shouldBounce(
            edge: edge,
            previousEdge: lastEdge,
            isDragging: hud.center.isHeld,
            sinceLastBounce: lastBounce.map { now - $0 }
        ) else { return }
        lastBounce = now
        edgeHits += 1
    }

    private var interaction: NotchHUDView.Interaction? {
        guard hud.isAdjustableOnScreen else { return nil }
        return NotchHUDView.Interaction(
            isDragging: hud.center.isHeld,
            onDrag: { level in
                hud.setDragging(true)
                hud.adjust(to: level)
            },
            onDragEnded: { hud.setDragging(false) }
        )
    }
}
