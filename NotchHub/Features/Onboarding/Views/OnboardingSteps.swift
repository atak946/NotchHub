import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            OnboardingNotchPreview()
            VStack(spacing: 10) {
                Text("NotchHub'a hoş geldin")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Çentiğin artık bir kontrol merkezi: dosya rafı, medya, zamanlayıcı, toplantılar ve notlar tek dokunuşta.")
                    .font(.system(size: 14))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

struct OnboardingCalendarSourcesStep: View {
    private static let internetAccountsURL = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                title: "Takvim kaynakları",
                subtitle: "Toplantıların nereden gelsin? İstediğin kadar kaynağı birleştirebilirsin."
            )
            sourceCard(
                icon: "person.crop.circle.badge.plus",
                title: "İnternet Hesapları",
                detail: "iCloud, Google, Exchange: macOS'a eklenen her hesap otomatik görünür.",
                buttonTitle: "İnternet Hesapları'nı aç"
            ) {
                if let url = Self.internetAccountsURL { openURL(url) }
            }
            sourceCard(
                icon: "link",
                title: "ICS aboneliği",
                detail: "Bir takvim bağlantısını (webcal / .ics) Ayarlar › Takvim'den ekle.",
                buttonTitle: "Takvim ayarları"
            ) {
                showSettings()
            }
            sourceCard(
                icon: "building.2",
                title: "Microsoft 365",
                detail: "İş hesabını cihaz koduyla bağla; parola NotchHub'a hiç girmez.",
                buttonTitle: "Hesap bağla"
            ) {
                showSettings()
            }
            Spacer(minLength: 0)
        }
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }

    private func sourceCard(
        icon: String,
        title: String,
        detail: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        OnboardingCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(OnboardingStyle.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(buttonTitle, action: action)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }
}

struct OnboardingDoneStep: View {
    private static let shortcuts: [(keys: String, label: String)] = [
        ("⌥⌘N", "Paneli aç / kapat"),
        ("Esc", "Paneli kapat"),
        ("⌘1…6", "Sekmeler arasında geç"),
    ]

    @Binding var launchAtLogin: Bool
    let launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                title: "Her şey hazır",
                subtitle: "Fareyi çentiğe getir ya da kısayolu kullan. Bu sihirbaz menü çubuğundan her zaman açılabilir."
            )
            OnboardingCard {
                VStack(spacing: 10) {
                    ForEach(Self.shortcuts, id: \.keys) { shortcut in
                        HStack {
                            Text(shortcut.label)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Text(shortcut.keys)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.1), in: .rect(cornerRadius: 6))
                        }
                    }
                }
            }
            OnboardingCard {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Girişte başlat", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .tint(OnboardingStyle.accent)
                        .foregroundStyle(.white)
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(OnboardingStyle.denied)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
