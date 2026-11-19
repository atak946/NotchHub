import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import NotchHub

struct HotKeyShortcutTests {
    private let cmdOpt = UInt32(cmdKey | optionKey)

    @Test func requiresCommandOptionOrControl() {
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: 0, keyLabel: "h") == nil)
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: UInt32(shiftKey), keyLabel: "h") == nil)
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: UInt32(controlKey), keyLabel: "h") != nil)
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: cmdOpt, keyLabel: " ") == nil)
    }

    @Test func displaysModifiersInAppleOrder() throws {
        let all = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let shortcut = try #require(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: all, keyLabel: "h"))
        #expect(shortcut.displayName == "⌃⌥⇧⌘H")
    }

    @Test func convertsAppKitFlags() {
        #expect(HotKeyShortcut.carbonModifiers(from: [.command, .option]) == cmdOpt)
        #expect(HotKeyShortcut.carbonModifiers(from: [.control, .shift]) == UInt32(controlKey | shiftKey))
        #expect(HotKeyShortcut.carbonModifiers(from: []) == 0)
    }

    @Test func labelsSpecialKeys() {
        #expect(HotKeyShortcut.label(forKeyCode: UInt16(kVK_F5), characters: "\u{F708}") == "F5")
        #expect(HotKeyShortcut.label(forKeyCode: UInt16(kVK_Space), characters: " ") == "Space")
        #expect(HotKeyShortcut.label(forKeyCode: UInt16(kVK_ANSI_K), characters: "k") == "k")
        #expect(HotKeyShortcut.label(forKeyCode: 200, characters: "\u{1B}") == nil)
    }

    @Test func rejectsTheAppsOwnShortcuts() throws {
        let panel = try #require(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: cmdOpt, keyLabel: "n"))
        let free = try #require(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: cmdOpt, keyLabel: "h"))
        #expect(ReservedHotKeys.isReserved(panel))
        #expect(!ReservedHotKeys.isReserved(free))
    }

    @MainActor
    @Test func persistsInSettings() throws {
        let defaults = try #require(UserDefaults(suiteName: "HotKeyShortcutTests.\(UUID().uuidString)"))
        let shortcut = try #require(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: cmdOpt, keyLabel: "h"))
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.notchToggleShortcut == nil)
        settings.notchToggleShortcut = shortcut
        #expect(SettingsStore(defaults: defaults).notchToggleShortcut == shortcut)
        settings.notchToggleShortcut = nil
        #expect(SettingsStore(defaults: defaults).notchToggleShortcut == nil)
    }
}
