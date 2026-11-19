import AppKit
import SwiftUI

/// Click, then press a key combination to assign it. Esc cancels, ⌫ clears.
struct HotKeyRecorderField: View {
    @Binding var shortcut: HotKeyShortcut?

    @State private var isRecording = false
    @State private var isHovered = false
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: SettingsTheme.Spacing.s) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: shortcut == nil || isRecording ? .default : .rounded))
                    .foregroundStyle(isRecording ? SettingsTheme.Palette.brand : SettingsTheme.Palette.textPrimary)
                    .frame(minWidth: 110)
                    .padding(.horizontal, SettingsTheme.Spacing.m)
                    .padding(.vertical, 5)
                    .background(fill, in: .rect(cornerRadius: SettingsTheme.Radius.s, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SettingsTheme.Radius.s, style: .continuous)
                            .strokeBorder(isRecording ? SettingsTheme.Palette.brand : SettingsTheme.Palette.hairline, lineWidth: 1)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("Kısayol: \(label)")
            .accessibilityHint("Yeni kısayol kaydetmek için tıklayın")

            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SettingsTheme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Kısayolu kaldır")
                .accessibilityLabel("Kısayolu kaldır")
            }
        }
        .animation(SettingsTheme.Motion.hover, value: isRecording)
        .animation(SettingsTheme.Motion.hover, value: hint)
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return String(localized: "Tuşlara basın…") }
        return shortcut?.displayName ?? String(localized: "Kısayol ata")
    }

    private var fill: Color {
        if isRecording { return SettingsTheme.Palette.brand.opacity(0.14) }
        return isHovered ? SettingsTheme.Palette.pressedFill : SettingsTheme.Palette.controlFill
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        hint = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = flags.subtracting([.capsLock, .numericPad, .function]).isEmpty
        if plain, event.keyCode == UInt16(53) { // Esc
            stopRecording()
            return
        }
        if plain, event.keyCode == UInt16(51) { // ⌫
            shortcut = nil
            stopRecording()
            return
        }
        guard let keyLabel = HotKeyShortcut.label(forKeyCode: event.keyCode, characters: event.charactersIgnoringModifiers),
              let recorded = HotKeyShortcut(
                  keyCode: UInt32(event.keyCode),
                  carbonModifiers: HotKeyShortcut.carbonModifiers(from: flags),
                  keyLabel: keyLabel
              )
        else {
            hint = String(localized: "⌃, ⌥ veya ⌘ ile birlikte basın")
            return
        }
        guard !ReservedHotKeys.isReserved(recorded) else {
            hint = String(localized: "\(recorded.displayName) zaten kullanılıyor")
            return
        }
        hint = nil
        shortcut = recorded
        stopRecording()
    }
}
