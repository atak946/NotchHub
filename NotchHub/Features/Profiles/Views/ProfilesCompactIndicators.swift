import SwiftUI

/// ≤ 14 × 14 glyph beside the closed notch: red eye while a remote session is detected,
/// otherwise a pulsing profile-colored dot while a profile runs. EmptyView when idle.
struct ProfilesCompactIndicators: View {
    let profiles: Profiles

    init(profiles: Profiles) {
        self.profiles = profiles
    }

    var body: some View {
        if profiles.remoteMonitor.hasCompactIndicator {
            RemoteSessionCompactIndicator(sources: profiles.remoteMonitor.activeSources)
        } else if let runState = profiles.service.runState {
            ProfileRunCompactIndicator(
                color: profiles.store.profile(id: runState.profileID)?.color.color ?? .white,
                label: "Profil çalışıyor, adım \(runState.progressText)"
            )
        } else {
            EmptyView()
        }
    }
}

private struct RemoteSessionCompactIndicator: View {
    let sources: [RemoteSessionSource]

    var body: some View {
        let names = sources.map(\.title).joined(separator: ", ")
        Image(systemName: "eye.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: ProfilesMetrics.compactSize, height: ProfilesMetrics.compactSize)
            .background(.red, in: .circle)
            .symbolEffect(.pulse)
            .help("Uzak oturum etkin (sezgisel): \(names)")
            .accessibilityLabel("Uzak oturum etkin: \(names)")
    }
}

private struct ProfileRunCompactIndicator: View {
    let color: Color
    let label: String
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: ProfilesMetrics.dotSize, height: ProfilesMetrics.dotSize)
            .scaleEffect(isPulsing ? 1 : 0.7)
            .opacity(isPulsing ? 1 : 0.6)
            .frame(width: ProfilesMetrics.compactSize, height: ProfilesMetrics.compactSize)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true }
            }
            .help(label)
            .accessibilityLabel(label)
    }
}
