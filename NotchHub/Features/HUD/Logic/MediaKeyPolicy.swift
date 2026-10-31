import CoreGraphics
import Foundation

/// What the current hardware lets NotchHub change itself. Each flag is only filled for the key kind asked about.
struct MediaKeyCapabilities: Equatable, Sendable {
    var canSetVolume = false
    var canSetMute = false
    /// The built-in display brightness can be both read and set.
    var canSetBrightness = false
}

/// A media key NotchHub performs instead of macOS.
enum MediaKeyCommand: Equatable, Sendable {
    case volumeUp(fine: Bool)
    case volumeDown(fine: Bool)
    case toggleMute
    case brightnessUp(fine: Bool)
    case brightnessDown(fine: Bool)
}

/// The event tap's verdict for one key event.
enum MediaKeyDecision: Equatable, Sendable {
    /// macOS handles the key (and shows its own HUD).
    case pass
    /// The event is swallowed; `nil` for a key-up, which has nothing to do.
    case consume(MediaKeyCommand?)
}

/// Volume and mute of the default output device.
struct VolumeState: Equatable, Sendable {
    var level: Double
    var isMuted: Bool
}

/// Pure decisions and step math for the media key interceptor, mirroring the macOS behaviour.
enum MediaKeyPolicy {
    static let coarseStepCount = 16
    static let fineStepCount = 64
    /// Absorbs float noise so a level already on the grid moves by exactly one step.
    /// In step units: DisplayServices reports brightness as a `Float` that can sit a few ULPs off the grid
    /// (0.75 reads back as 0.7499999 → 11.999998 steps), which a 1e-6 tolerance missed and pinned the level.
    private static let gridTolerance = 1e-3

    /// Interception needs the notch HUD, the "hide macOS HUD" setting and Accessibility trust.
    static func isActive(hudEnabled: Bool, hidesSystemHUD: Bool, isTrusted: Bool) -> Bool {
        hudEnabled && hidesSystemHUD && isTrusted
    }

    /// Option+Shift selects quarter steps, as in macOS.
    static func isFineModifier(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate) && flags.contains(.maskShift)
    }

    /// The level kind a key controls, or `nil` for keys that always pass through.
    static func controlledKind(of key: SystemDefinedKeyEvent.Key) -> HUDKind? {
        switch key {
        case .soundUp, .soundDown, .mute: .volume
        case .brightnessUp, .brightnessDown: .brightness
        case .illuminationUp, .illuminationDown, .illuminationToggle: nil
        }
    }

    /// Consume only what NotchHub can perform; a key-up is consumed whenever its key-down would be.
    static func decide(
        _ event: SystemDefinedKeyEvent,
        isFine: Bool,
        capabilities: MediaKeyCapabilities
    ) -> MediaKeyDecision {
        guard let key = event.key, let command = command(for: key, isFine: isFine, capabilities: capabilities) else {
            return .pass
        }
        return .consume(event.isKeyDown ? command : nil)
    }

    static func stepSize(isFine: Bool) -> Double {
        1.0 / Double(isFine ? fineStepCount : coarseStepCount)
    }

    /// One step up or down on the step grid, clamped to 0…1. Off-grid levels snap to the next grid point.
    static func stepped(_ level: Double, up: Bool, isFine: Bool) -> Double {
        let count = Double(isFine ? fineStepCount : coarseStepCount)
        let position = HUDLevel.clamped(level) * count
        let target = up
            ? (position + gridTolerance).rounded(.down) + 1
            : (position - gridTolerance).rounded(.up) - 1
        return HUDLevel.clamped(target / count)
    }

    /// The new volume state; raising the volume while muted unmutes, as macOS does.
    static func apply(_ command: MediaKeyCommand, to state: VolumeState, canSetMute: Bool) -> VolumeState {
        switch command {
        case .volumeUp(let fine):
            let unmute = state.isMuted && canSetMute
            return VolumeState(level: stepped(state.level, up: true, isFine: fine), isMuted: unmute ? false : state.isMuted)
        case .volumeDown(let fine):
            return VolumeState(level: stepped(state.level, up: false, isFine: fine), isMuted: state.isMuted)
        case .toggleMute:
            return canSetMute ? VolumeState(level: state.level, isMuted: !state.isMuted) : state
        case .brightnessUp, .brightnessDown:
            return state
        }
    }

    private static func command(
        for key: SystemDefinedKeyEvent.Key,
        isFine: Bool,
        capabilities: MediaKeyCapabilities
    ) -> MediaKeyCommand? {
        switch key {
        case .soundUp: capabilities.canSetVolume ? .volumeUp(fine: isFine) : nil
        case .soundDown: capabilities.canSetVolume ? .volumeDown(fine: isFine) : nil
        case .mute: capabilities.canSetMute ? .toggleMute : nil
        case .brightnessUp: capabilities.canSetBrightness ? .brightnessUp(fine: isFine) : nil
        case .brightnessDown: capabilities.canSetBrightness ? .brightnessDown(fine: isFine) : nil
        case .illuminationUp, .illuminationDown, .illuminationToggle: nil
        }
    }
}
