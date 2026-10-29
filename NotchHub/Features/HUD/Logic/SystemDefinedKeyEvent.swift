import Foundation

/// A media/brightness key decoded from an `NSEvent.systemDefined` event (subtype 8, "aux control button").
///
/// `data1` layout: bits 16–31 key code (`NX_KEYTYPE_*`), bits 8–15 key state (0x0A down, 0x0B up),
/// bit 0 repeat flag.
struct SystemDefinedKeyEvent: Equatable, Sendable {
    static let auxControlButtonsSubtype: Int16 = 8
    private static let keyDownState: UInt32 = 0x0A
    private static let keyUpState: UInt32 = 0x0B

    /// `NX_KEYTYPE_*` values from IOKit/hidsystem/ev_keymap.h.
    enum Key: Int, Sendable {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case illuminationUp = 21
        case illuminationDown = 22
        case illuminationToggle = 23
    }

    let keyCode: Int
    let isKeyDown: Bool
    let isRepeat: Bool

    /// `nil` for other subtypes or an unknown key state.
    static func decode(subtype: Int16, data1: Int) -> SystemDefinedKeyEvent? {
        guard subtype == auxControlButtonsSubtype else { return nil }
        let bits = UInt32(truncatingIfNeeded: data1)
        let keyCode = Int((bits & 0xFFFF_0000) >> 16)
        let flags = bits & 0x0000_FFFF
        let state = (flags & 0xFF00) >> 8
        guard state == keyDownState || state == keyUpState else { return nil }
        return SystemDefinedKeyEvent(keyCode: keyCode, isKeyDown: state == keyDownState, isRepeat: flags & 0x1 == 1)
    }

    var key: Key? { Key(rawValue: keyCode) }

    /// The HUD this key press should show; only key-down (including auto-repeat) counts.
    var hudKind: HUDKind? {
        guard isKeyDown, let key else { return nil }
        switch key {
        case .soundUp, .soundDown, .mute: return .volume
        case .brightnessUp, .brightnessDown: return .brightness
        case .illuminationUp, .illuminationDown, .illuminationToggle: return .keyboardBacklight
        }
    }
}
