import SwiftUI

/// "Sources" settings: per-source diagnostics, EventKit status with the Internet Accounts hint,
/// ICS feeds and Microsoft 365 sign-in.
struct CalendarSourcesSection: View {
    private let calendar: CalendarService

    init(calendar: CalendarService) {
        self.calendar = calendar
    }

    var body: some View {
        Section {
            ForEach(calendar.sourceDiagnostics) { diagnostic in
                LabeledContent {
                    Text(diagnostic.summary)
                        .foregroundStyle(diagnostic.message == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label(diagnostic.name, systemImage: diagnostic.systemImage)
                }
            }
            LabeledContent("macOS Takvim") {
                eventKitStatus
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Sistem Ayarları › İnternet Hesapları'na Microsoft Exchange eklediğinizde Outlook toplantıları burada otomatik görünür. Mac için yeni Outlook takvimini macOS ile paylaşmaz — bunun yerine aşağıdaki ICS akışını veya Microsoft 365'i kullanın.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("İnternet Hesapları'nı Aç") { calendar.openInternetAccounts() }
            }
        } header: {
            Text("Kaynaklar")
        }

        if let feeds = calendar.icsFeedSource {
            ICSFeedsSettingsSection(source: feeds)
        }
        if let microsoft = calendar.microsoftSource {
            MicrosoftAccountSettingsSection(source: microsoft)
        }
    }

    @ViewBuilder
    private var eventKitStatus: some View {
        switch calendar.primaryAuthorization {
        case .authorized:
            Label("İzin verildi", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notDetermined:
            Button("İzin Ver") { calendar.requestAccess() }
        case .denied:
            HStack {
                Text("Reddedildi").foregroundStyle(.secondary)
                Button("Ayarları Aç") { calendar.openPrivacySettings() }
            }
        }
    }
}
