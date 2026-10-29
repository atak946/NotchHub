import SwiftUI

/// Menu button listing output devices; the icon reflects the current default (AirPods, speakers, ...).
struct AudioOutputMenu: View {
    let audio: AudioOutputService

    @State private var isHovered = false

    var body: some View {
        Menu {
            if audio.devices.isEmpty {
                Text("Çıkış aygıtı yok")
            }
            ForEach(audio.devices) { device in
                Button {
                    audio.setDefault(device)
                } label: {
                    Label(device.name, systemImage: device.isDefault ? "checkmark" : device.systemImage)
                }
            }
        } label: {
            Image(systemName: audio.defaultDevice?.systemImage ?? "speaker.wave.2")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(isHovered ? 1 : 0), in: .circle)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(PressScaleButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.primary)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(audio.defaultDevice.map { "Çıkış: \($0.name)" } ?? "Ses çıkışı")
        .accessibilityLabel("Ses çıkışı")
    }
}
