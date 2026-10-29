import SwiftUI

/// Settings form sections for the calendar module: reminders, access, grouping, sources and visible calendars.
struct CalendarSettingsSection: View {
    @Bindable private var calendar: CalendarService

    init(calendar: CalendarService) {
        self.calendar = calendar
    }

    var body: some View {
        Section("Sıradaki Toplantı") {
            Picker("Hatırlatıcı", selection: $calendar.reminderLeadTime) {
                ForEach(CalendarService.reminderLeadTimeOptions, id: \.self) { lead in
                    Text(Self.title(forLeadTime: lead)).tag(lead)
                }
            }
            Picker("Bugünün etkinliklerini grupla", selection: $calendar.grouping) {
                ForEach(CalendarGrouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
        }

        CalendarSourcesSection(calendar: calendar)

        if calendar.authorization == .authorized {
            Section("Takvimler") {
                if calendar.accounts.isEmpty {
                    Text("Takvim bulunamadı. Sistem Ayarları › İnternet Hesapları'ndan hesap, ICS akışı veya yukarıdan Microsoft 365 ekleyin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(calendar.accounts) { account in
                    Label(account.displayTitle, systemImage: account.kind.systemImage)
                        .font(.headline)
                    ForEach(calendar.calendars(for: account)) { info in
                        Toggle(isOn: visibilityBinding(info.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(info.color.color)
                                    .frame(width: 8, height: 8)
                                Text(info.title)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }

    private func visibilityBinding(_ calendarID: String) -> Binding<Bool> {
        Binding(
            get: { !calendar.isCalendarHidden(calendarID) },
            set: { calendar.setCalendar(calendarID, visible: $0) }
        )
    }

    nonisolated static func title(forLeadTime lead: TimeInterval) -> String {
        guard lead > 0 else { return "Kapalı" }
        let minutes = Int(lead / 60)
        return minutes == 1 ? "1 dakika önce" : "\(minutes) dakika önce"
    }
}
