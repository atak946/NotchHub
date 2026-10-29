import SwiftUI

struct OnboardingPermissionsStep: View {
    let permissions: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                title: "İzinler",
                subtitle: "Yalnızca kullandığın özellikler için izin ver. Durum canlı güncellenir."
            )
            VStack(spacing: OnboardingStyle.rowSpacing) {
                ForEach(AppPermission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        status: permissions.status(of: permission),
                        isBusy: permissions.inFlight.contains(permission),
                        onRequest: { Task { await permissions.request(permission) } },
                        onOpenSettings: { permissions.openSettings(for: permission) }
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PermissionRow: View {
    let permission: AppPermission
    let status: PermissionStatus
    let isBusy: Bool
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        OnboardingCard {
            HStack(spacing: 12) {
                Image(systemName: permission.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(permission.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        if permission.isOptional {
                            Text("isteğe bağlı")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(OnboardingStyle.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.white.opacity(0.07), in: .capsule)
                        }
                    }
                    Text(permission.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                statusBadge
                actionButton
                    .frame(minWidth: 92, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        Label(status.title, systemImage: OnboardingStyle.symbol(for: status))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(OnboardingStyle.color(for: status))
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy, value: status)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .granted:
            EmptyView()
        case .notDetermined:
            Button(action: onRequest) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text("İzin ver")
                }
            }
            .buttonStyle(OnboardingSecondaryButtonStyle())
            .disabled(isBusy)
        case .denied:
            Button("Ayarları aç", action: onOpenSettings)
                .buttonStyle(OnboardingSecondaryButtonStyle())
        }
    }
}
