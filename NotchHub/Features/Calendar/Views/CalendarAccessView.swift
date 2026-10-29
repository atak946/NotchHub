import SwiftUI

/// Explains why calendar access is needed and offers the right next step.
struct CalendarAccessView: View {
    let calendar: CalendarService

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 6) {
                Text(isDenied ? "Takvim erişimi kapalı" : "Sıradaki toplantınızı burada görün")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("NotchHub, yaklaşan toplantıları ve katılım bağlantılarını göstermek için takvimlerinizi okur. Hesapları Sistem Ayarları › İnternet Hesapları'ndan, ICS akışı / Microsoft 365'i ise NotchHub Ayarları'ndan ekleyin.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                actions
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var isDenied: Bool { calendar.authorization == .denied }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if isDenied {
                Button { calendar.openPrivacySettings() } label: {
                    CalendarProminentButtonLabel(title: "Ayarları Aç", systemImage: "gearshape.fill", tint: .accentColor)
                }
                .buttonStyle(CalendarPressableStyle())
                .help("Gizlilik ve Güvenlik › Takvimler'i Aç")
            } else {
                Button { calendar.requestAccess() } label: {
                    CalendarProminentButtonLabel(title: "İzin Ver", systemImage: "calendar", tint: .accentColor)
                }
                .buttonStyle(CalendarPressableStyle())
                .help("macOS'ten takvim erişimi iste")
                Button("Ayarları Aç") { calendar.openPrivacySettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
}
