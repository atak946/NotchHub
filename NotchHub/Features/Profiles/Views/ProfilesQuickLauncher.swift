import SwiftUI

/// Panel quick launcher: up to 6 profiles as colored chips. Click runs (or cancels the running one);
/// context menu offers Deactivate. Active profile chip is filled.
struct ProfilesQuickLauncher: View {
    let profiles: Profiles

    init(profiles: Profiles) {
        self.profiles = profiles
    }

    private var service: ProfilesService { profiles.service }

    var body: some View {
        let items = profiles.store.quickLaunchProfiles
        if items.isEmpty {
            Label("Ayarlar'da müşteri profilleri oluşturun", systemImage: "briefcase")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            FlowChips(items: items) { profile in
                ProfileChip(
                    profile: profile,
                    isActive: profiles.store.activeProfileID == profile.id,
                    runState: service.runState?.profileID == profile.id ? service.runState : nil,
                    isDisabled: service.isRunning && !service.isRunning(profile.id),
                    onTap: { tap(profile) },
                    onDeactivate: profile.deactivateSteps.isEmpty ? nil : { service.deactivate(profile.id) }
                )
            }
        }
    }

    private func tap(_ profile: ClientProfile) {
        if service.isRunning(profile.id) {
            service.cancel()
        } else {
            service.activate(profile.id)
        }
    }
}

/// Two rows of three chips at most (6 profiles); keeps the panel height predictable.
private struct FlowChips<Content: View>: View {
    static var columns: Int { 3 }

    let items: [ClientProfile]
    @ViewBuilder let content: (ClientProfile) -> Content

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(stride(from: 0, to: items.count, by: Self.columns)), id: \.self) { start in
                GridRow {
                    ForEach(items[start..<min(start + Self.columns, items.count)]) { content($0) }
                }
            }
        }
    }
}

private struct ProfileChip: View {
    let profile: ClientProfile
    let isActive: Bool
    let runState: ProfilesService.RunState?
    let isDisabled: Bool
    let onTap: () -> Void
    let onDeactivate: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        let tint = profile.color.color
        Button(action: onTap) {
            HStack(spacing: 6) {
                if runState != nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(tint).frame(width: ProfilesMetrics.dotSize, height: ProfilesMetrics.dotSize)
                }
                Text(profile.displayName)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                if let runState {
                    Text(runState.progressText)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: ProfilesMetrics.chipHeight)
            .background(chipFill(tint), in: .capsule)
            .overlay(Capsule().strokeBorder(tint.opacity(isHovered ? 0.9 : 0.45), lineWidth: 1))
            .foregroundStyle(.primary)
        }
        .buttonStyle(ProfilesPressableStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .animation(ProfilesMetrics.animation, value: isHovered)
        .help(runState == nil ? "\(profile.displayName) çalıştır" : "\(profile.displayName) iptal et")
        .contextMenu {
            if let onDeactivate {
                Button("Devre dışı bırak", systemImage: "stop.circle", action: onDeactivate)
            }
        }
        .accessibilityLabel(isActive ? Text("\(profile.displayName), etkin") : Text(verbatim: profile.displayName))
    }

    private func chipFill(_ tint: Color) -> Color {
        isActive ? tint.opacity(0.55) : Color.primary.opacity(isHovered ? 0.14 : 0.08)
    }
}
