import CoreGraphics
import Observation

@MainActor
@Observable
final class NotchViewModel {
    var geometry: NotchGeometry
    var isExpanded = false
    /// Incremented to play the attention (shake) animation.
    var attentionCount = 0
    /// Collapsed media control under the pointer, set by the controller from geometry.
    var hoveredMediaControl: MediaControlAction?
    /// Press counters that drive the bounce feedback of the collapsed media controls.
    private(set) var mediaControlPresses: [MediaControlAction: Int] = [:]
    /// Pointer is over the collapsed meeting mic button.
    var isMicMuteHovered = false
    private var selectedModule: NotchModule?
    /// Set by the controller: expands the panel on the given module.
    @ObservationIgnored var onOpenModule: ((NotchModule) -> Void)?

    let settings: SettingsStore
    let services: ModuleServices

    init(geometry: NotchGeometry, settings: SettingsStore, services: ModuleServices) {
        self.geometry = geometry
        self.settings = settings
        self.services = services
    }

    var enabledModules: [NotchModule] {
        NotchModule.allCases.filter(settings.isEnabled)
    }

    /// The selected module, falling back to the first enabled one when it was turned off.
    var activeModule: NotchModule? {
        if let selectedModule, settings.isEnabled(selectedModule) {
            return selectedModule
        }
        return enabledModules.first
    }

    func select(_ module: NotchModule) {
        selectedModule = module
    }

    var hasCompactContent: Bool {
        services.hasCompactMedia || services.hasCompactTimer || services.hasCompactIndicators
    }

    var showsMediaControls: Bool {
        CompactMediaControls.isAvailable(
            isEnabled: settings.showsCompactMediaControls,
            hasActiveTrack: services.hasCompactMedia
        )
    }

    func registerPress(_ action: MediaControlAction) {
        mediaControlPresses = mediaControlPresses.merging([action: 1], uniquingKeysWith: +)
    }

    /// Mic mute button on the right wing while a meeting is detected.
    var showsMicMuteButton: Bool {
        let system = services.system
        return CompactMicMute.isAvailable(
            isInMeeting: settings.isEnabled(.status) && system.meetingMode.hasCompactIndicator,
            isControlAvailable: system.micMute.isAvailable
        )
    }

    /// Widest for the media controls; wider when status glyphs share the right wing with the timer.
    var wingWidth: CGFloat {
        guard hasCompactContent else { return 0 }
        return CompactMicMute.wingWidth(base: baseWingWidth, isAvailable: showsMicMuteButton)
    }

    private var baseWingWidth: CGFloat {
        if showsMediaControls { return NotchGeometry.mediaControlsWingWidth }
        return services.hasCompactIndicators ? NotchGeometry.wideCompactWingWidth : NotchGeometry.compactWingWidth
    }
}
