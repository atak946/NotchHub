import SwiftUI

/// Crossed-out bell beside the closed notch while notifications are muted.
struct MuteCompactIndicator: View {
    private static let size: CGFloat = 14

    let mute: AlertMuteService

    var body: some View {
        if let reason = mute.reason {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: Self.size, height: Self.size)
                .help(reason.title)
                .accessibilityLabel(reason.title)
        }
    }
}

/// `Section("Sessiz Mod")` for the settings Form.
struct MuteSettingsSection: View {
    @Bindable var mute: AlertMuteService

    var body: some View {
        Section("Sessiz Mod") {
            LabeledContent("Bildirimleri sustur") {
                if let reason = mute.reason {
                    HStack {
                        Label(reason.title, systemImage: "bell.slash.fill")
                            .foregroundStyle(.secondary)
                        Button("Susturmayı kapat") { mute.unmute() }
                    }
                } else {
                    Menu("Sustur") {
                        ForEach(AlertMuteDuration.allCases) { duration in
                            Button(duration.title) { mute.mute(for: duration) }
                        }
                    }
                    .fixedSize()
                }
            }
            Toggle("Toplantılarda sustur", isOn: $mute.mutesInMeetings)
                .help("Toplantı algılama, Toplantı sayfasından açık olmalı.")
            Toggle("Odak (Pomodoro) sırasında sustur", isOn: $mute.mutesInFocus)
            Toggle("Toplantı hatırlatıcıları ve biten zamanlayıcılar yine gösterilsin", isOn: $mute.allowsTimeSensitive)
            Text("Susturulurken gelen bildirimler bellekte tutulur ve sonunda özetlenir. Güvenlik ve pil uyarıları her zaman gösterilir. macOS afişlerini yalnızca Bildirimler sayfasındaki \"macOS bildirimlerini gizle\" açıkken gizler; tamamen engellemek için macOS Odak'ı kullan.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
