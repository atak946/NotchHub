import SwiftUI

/// Small "Ayna" pill in the next-event card that opens the camera mirror.
struct CameraMirrorCardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Ayna", systemImage: "person.crop.square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(.quaternary.opacity(0.8), in: .capsule)
        }
        .buttonStyle(CalendarPressableStyle())
        .help("Kamerayı kontrol et")
    }
}
