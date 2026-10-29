import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Insights settings pieces, placed on separate Settings pages: the Accessibility permission row,
/// unread badges (Okunmamış Mesajlar) and time tracking (Zaman Takibi).
struct AccessibilityAccessRow: View {
    let insights: Insights

    var body: some View {
        LabeledContent("Erişilebilirlik izni") {
            if insights.isAccessibilityTrusted {
                Label("İzin verildi", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Button("Erişilebilirlik İzni Ver") { insights.requestAccessibilityAccess() }
                    Button("Yeniden kontrol et") { insights.refreshAccessibilityTrust() }
                }
            }
        }
        if !insights.isAccessibilityTrusted {
            Text("Dock rozetlerini, bildirimleri ve pencere başlıklarını okumak için gerekir. İzin yoksa okunmamış sayıları gizlenir ve yalnızca uygulama kuralları zamanı takip eder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct UnreadSettingsSection: View {
    @Bindable var monitor: UnreadBadgeMonitor
    @State private var newApp = ""

    var body: some View {
        Section("Okunmamış rozetleri") {
            Toggle("Okunmamış rozetlerini göster", isOn: $monitor.isEnabled)
            Toggle("Yeni mesajlarda uyar", isOn: $monitor.alertsEnabled)
                .disabled(!monitor.isEnabled)
            Stepper(value: $monitor.pollSeconds, in: UnreadBadgeMonitor.pollSecondsRange) {
                LabeledContent("Kontrol aralığı") {
                    Text("\(monitor.pollSeconds) s").monospacedDigit()
                }
            }
            ForEach(monitor.watchedApps, id: \.self) { app in
                HStack {
                    Text(app)
                    Spacer()
                    Button(role: .destructive) {
                        monitor.removeWatchedApp(app)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("\(app) izlemeyi bırak")
                }
            }
            HStack {
                TextField("Dock'ta görünen uygulama adı", text: $newApp)
                    .onSubmit(addApp)
                Button("Ekle", action: addApp)
                    .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addApp() {
        monitor.addWatchedApp(newApp)
        newApp = ""
    }
}

struct TimeTrackingSettingsSection: View {
    @Bindable var tracker: TimeTracker
    @State private var isConfirmingReset = false
    @State private var exportError: String?

    var body: some View {
        Section("Zaman takibi") {
            Toggle("Faturalanabilir zamanı takip et", isOn: $tracker.isEnabled)
            Stepper(value: $tracker.idleThresholdMinutes, in: TimeTracker.idleThresholdRange) {
                LabeledContent("Boşta kalınca duraklat") {
                    Text("\(tracker.idleThresholdMinutes) dk").monospacedDigit()
                }
            }
            Toggle("Hafta içi özet hatırlatıcısı", isOn: $tracker.reminderEnabled)
            DatePicker("Hatırlatma saati", selection: reminderTime, displayedComponents: .hourAndMinute)
                .disabled(!tracker.reminderEnabled)
            Text("Yalnızca eşleşen müşteri ve uygulama saklanır; pencere başlıkları veya yollar asla saklanmaz.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Takip kuralları") {
            if tracker.rules.isEmpty {
                Text("Bir kural ekleyin, örn. pencere başlığı “NorthwindServices” içeriyorsa → müşteri “Northwind”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($tracker.rules) { $rule in
                TrackingRuleRow(rule: $rule) { tracker.removeRule(id: rule.id) }
            }
            Button("Kural ekle", systemImage: "plus") { tracker.addRule() }
            Text("Belge yolu kuralları pencere başlığı kurallarından, onlar da uygulama kurallarından önceliklidir; eşitlikte listede önce gelen kural geçerlidir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Takip verileri") {
            HStack {
                Button("Haftayı CSV olarak dışa aktar…", action: exportWeek)
                Spacer()
                Button("Verileri sıfırla…", role: .destructive) { isConfirmingReset = true }
            }
            if let message = exportError ?? tracker.lastError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog("Tüm takip edilen zaman silinsin mi?", isPresented: $isConfirmingReset) {
            Button("Sil", role: .destructive) { tracker.resetData() }
        } message: {
            Text("Bu işlem geri alınamaz. Kurallar korunur.")
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: tracker.schedule.hour, minute: tracker.schedule.minute, second: 0, of: Date()
            ) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            tracker.schedule = DailySummarySchedule(
                hour: parts.hour ?? DailySummarySchedule.defaultHour,
                minute: parts.minute ?? DailySummarySchedule.defaultMinute
            )
        }
    }

    private func exportWeek() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "NotchHub-time-week-of-\(tracker.todayKey).csv"
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tracker.exportWeekCSV().write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
        } catch {
            exportError = String(localized: "Dışa aktarma başarısız: \(error.localizedDescription)")
        }
    }
}

struct TrackingRuleRow: View {
    @Binding var rule: TrackingRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Eşleşme", selection: $rule.matchType) {
                ForEach(TrackingRule.MatchType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            TextField("Desen", text: $rule.pattern)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            TextField("Müşteri", text: $rule.client)
                .frame(maxWidth: 100)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Kuralı sil")
        }
        .opacity(rule.isValid ? 1 : 0.6)
    }
}
