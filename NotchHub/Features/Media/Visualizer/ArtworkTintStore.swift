import AppKit
import Observation

/// Computes and caches the bar tint per artwork image, off the main actor.
/// Keyed by image identity: `MediaService` reuses one `NSImage` per artwork, and each entry keeps
/// its image alive so an identifier can never be reused by a different image while cached.
@MainActor
@Observable
final class ArtworkTintStore {
    static let shared = ArtworkTintStore()
    static let capacity = 32

    private struct Entry {
        let image: NSImage
        let tint: RGBColor
    }

    /// Bumped whenever a tint lands so views reading `tint(for:)` refresh.
    private(set) var revision = 0

    @ObservationIgnored private var cache = BoundedCache<ObjectIdentifier, Entry>(capacity: ArtworkTintStore.capacity)
    @ObservationIgnored private var inFlight: Set<ObjectIdentifier> = []
    @ObservationIgnored private let extract: @Sendable (CGImage?) -> RGBColor

    init(extract: @escaping @Sendable (CGImage?) -> RGBColor = ArtworkTint.tint(for:)) {
        self.extract = extract
    }

    /// Cached tint, or white until `prepare` finishes (and when there is no artwork).
    func tint(for image: NSImage?) -> RGBColor {
        _ = revision
        guard let image else { return .white }
        return cache.value(for: ObjectIdentifier(image))?.tint ?? .white
    }

    /// Computes the tint once per artwork; repeated calls for a cached or pending image are free.
    func prepare(_ image: NSImage) async {
        let key = ObjectIdentifier(image)
        guard cache.value(for: key) == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let extract = extract
        let tint = await Task.detached(priority: .utility) { extract(cgImage) }.value
        inFlight.remove(key)
        cache.insert(Entry(image: image, tint: tint), for: key)
        revision &+= 1
    }
}
