import AppKit
import Carbon.HIToolbox

/// A user-assigned global shortcut: a key plus at least one of ⌃ ⌥ ⌘ (⇧ alone is not enough).
struct HotKeyShortcut: Codable, Equatable, Sendable {
    /// Virtual key code (`kVK_*`).
    let keyCode: UInt32
    /// Carbon modifier mask (`cmdKey | optionKey | …`), as `RegisterEventHotKey` expects.
    let carbonModifiers: UInt32
    /// The key as typed when recorded, e.g. "N" or "F5".
    let keyLabel: String

    private static let requiredModifiers = UInt32(cmdKey | optionKey | controlKey)

    /// `nil` when the press cannot be a global shortcut (no ⌃/⌥/⌘, or an unusable key).
    init?(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        let label = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard carbonModifiers & Self.requiredModifiers != 0, !label.isEmpty else { return nil }
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = label
    }

    /// "⌃⌥⇧⌘N", in Apple's canonical modifier order.
    var displayName: String {
        let symbols: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        let prefix = symbols.filter { carbonModifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        return prefix + keyLabel
    }

    /// Converts AppKit modifier flags to the Carbon mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        return UInt32(mask)
    }

    /// Readable label for keys whose typed character is invisible or misleading.
    static func label(forKeyCode keyCode: UInt16, characters: String?) -> String? {
        if let special = specialKeyLabels[Int(keyCode)] { return special }
        guard let characters, let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        return characters
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// Shortcuts the app already registers; a recorded one must not collide with them.
enum ReservedHotKeys {
    static let panel = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(cmdKey | optionKey), keyLabel: "N")
    static let micMute = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey | optionKey), keyLabel: "M")

    static func isReserved(_ shortcut: HotKeyShortcut) -> Bool {
        [panel, micMute].compactMap { $0 }.contains {
            $0.keyCode == shortcut.keyCode && $0.carbonModifiers == shortcut.carbonModifiers
        }
    }
}
