import SwiftUI

/// Bare mic glyph on the collapsed right wing during meetings: green when live, orange with a slash when muted.
/// Clicks arrive through `NotchMicMuteCoordinator`'s catcher, so this view only draws.
struct MicMuteWingButton: View {
    private static let symbolSize: CGFloat = 13

    let isMuted: Bool
    let isHovered: Bool

    var body: some View {
        Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
            .font(.system(size: Self.symbolSize, weight: .semibold))
            .foregroundStyle(MicMuteTint.color(isMuted: isMuted))
            .contentTransition(.symbolEffect(.replace))
            .scaleEffect(isHovered ? 1.15 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.2), value: isMuted)
            .frame(width: NotchGeometry.micMuteButtonWidth)
            .help(isMuted ? "Mikrofonu aç (\(MicMuteHotKey.displayName))" : "Mikrofonu sustur (\(MicMuteHotKey.displayName))")
            .accessibilityElement()
            .accessibilityLabel(isMuted ? "Mikrofon kapalı" : "Mikrofon açık")
            .accessibilityAddTraits(.isButton)
    }
}

/// Mic state colors: green while live, orange while muted.
enum MicMuteTint {
    static func color(isMuted: Bool) -> Color { isMuted ? .orange : .green }
}

/// Small mute toggle overlaid on the Mic & Camera status tile.
struct MicMuteTileButton: View {
    private static let size: CGFloat = 22

    let controller: MicMuteController
    @State private var isHovered = false

    var body: some View {
        let isMuted = controller.isMuted
        let tint = MicMuteTint.color(isMuted: isMuted)
        Button {
            controller.toggle()
        } label: {
            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: Self.size, height: Self.size)
                .background(tint.opacity(isHovered ? 0.35 : 0.18), in: .circle)
                .overlay(Circle().strokeBorder(tint.opacity(isHovered ? 0.7 : 0.35), lineWidth: 1))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!controller.isAvailable)
        .opacity(controller.isAvailable ? 1 : 0.4)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(isMuted ? "Mikrofonu aç (\(MicMuteHotKey.displayName))" : "Mikrofonu sustur (\(MicMuteHotKey.displayName))")
        .accessibilityLabel(isMuted ? "Mikrofonu aç" : "Mikrofonu sustur")
    }
}

/// `Section("Mikrofonu Sustur")` for the settings Form.
struct MicMuteSettingsSection: View {
    @Bindable var controller: MicMuteController

    init(controller: MicMuteController) {
        self.controller = controller
    }

    var body: some View {
        Section("Mikrofonu Sustur") {
            Toggle("\(MicMuteHotKey.displayName) ile mikrofonu sustur / aç", isOn: $controller.isHotKeyEnabled)
            Text("Varsayılan giriş aygıtını sistem genelinde susturur; Zoom, Teams, Meet ve diğer tüm uygulamalarda geçerlidir. Toplantı sırasında çentiğin sağında mikrofon düğmesi görünür. NotchHub kapanınca mikrofon eski haline döner.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
