import SwiftUI

/// The mirror below the notch band: a rounded live preview, or the permission / error state in the same frame.
struct CameraMirrorView: View {
    private static let cornerRadius: CGFloat = 14

    let service: CameraMirrorService
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight + NotchGeometry.cameraMirrorTopGap)
            content
                .frame(
                    width: NotchGeometry.cameraMirrorPreviewSize.width,
                    height: NotchGeometry.cameraMirrorPreviewSize.height
                )
                .background(.white.opacity(0.06))
                .clipShape(.rect(cornerRadius: Self.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
                }
                .overlay(alignment: .topTrailing) {
                    AlertCloseButton { service.close() }
                        .padding(6)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kamera aynası")
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .live:
            if let session = service.previewSession {
                CameraPreviewView(session: session)
            }
        case .requestingAccess:
            MirrorMessage(systemImage: "video", text: "Kamera izni isteniyor…")
        case .denied:
            VStack(spacing: 8) {
                MirrorMessage(systemImage: "video.slash.fill", text: "Kamera izni yok")
                Button("Ayarları Aç") { service.openPrivacySettings() }
                    .buttonStyle(AlertActionButtonStyle(tint: .orange))
            }
        case .unavailable:
            MirrorMessage(systemImage: "video.slash", text: "Kamera kullanılamıyor")
        case .closed:
            Color.clear
        }
    }
}

private struct MirrorMessage: View {
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.75))
    }
}
