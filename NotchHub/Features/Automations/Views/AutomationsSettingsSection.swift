import AppKit
import SwiftUI

/// Settings form sections for Focus Guard and Capture Catcher.
struct AutomationsSettingsSection: View {
    let automations: Automations

    init(automations: Automations) {
        self.automations = automations
    }

    var body: some View {
        FocusGuardSettingsSection(service: automations.focusGuard)
        CaptureCatcherSettingsSection(service: automations.captureCatcher)
    }
}

struct FocusGuardSettingsSection: View {
    @Bindable var service: FocusGuardService

    var body: some View {
        Section("Odak Koruma") {
            Toggle("Odak sırasında dikkat dağıtan bir uygulama açtığımda hatırlat", isOn: $service.isEnabled)
            Picker("Aynı uygulama için şu süre içinde tekrarlama", selection: $service.cooldown) {
                ForEach(FocusGuardPolicy.cooldownOptions, id: \.self) { seconds in
                    Text(Self.title(forCooldown: seconds)).tag(seconds)
                }
            }
            .disabled(!service.isEnabled)
            FocusAppListEditor(service: service)
                .disabled(!service.isEnabled)
            Text("Yalnızca Pomodoro odak aşaması sürerken etkindir; ilk \(Int(service.policy.gracePeriod)) saniye yok sayılır.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    nonisolated static func title(forCooldown seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) saniye" : "\(Int(seconds / 60)) dk"
    }
}

struct CaptureCatcherSettingsSection: View {
    @Bindable var service: CaptureCatcherService

    var body: some View {
        Section("Ekran Görüntüleri ve İndirilenler") {
            Toggle("Yeni ekran görüntülerini ve indirilenleri rafa öner", isOn: $service.isEnabled)
            Group {
                Toggle("Ekran görüntülerini izle", isOn: $service.watchScreenshots)
                Toggle("Ekran görüntülerini rafa otomatik ekle", isOn: $service.autoAddScreenshots)
                    .disabled(!service.watchScreenshots)
                Toggle("İndirilenleri izle", isOn: $service.watchDownloads)
                Toggle("Alt klasörleri dahil et", isOn: $service.includeSubfolders)
                LabeledContent("Ekran görüntüsü klasörü", value: Self.displayPath(service.systemScreenshotFolder))
                if let shottr = service.detectedShottrFolder {
                    LabeledContent("Shottr klasörü", value: Self.displayPath(shottr))
                }
                customFolderRow
            }
            .disabled(!service.isEnabled)
            if service.isEnabled, !service.protectedFolders.isEmpty {
                Text("macOS, şu klasörlere erişim için bir kez izin isteyebilir: \(service.protectedFolders.map(Self.displayPath).joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var customFolderRow: some View {
        LabeledContent("Ek klasör") {
            HStack {
                if let folder = service.customScreenshotFolder {
                    Text(Self.displayPath(folder)).foregroundStyle(.secondary)
                    Button("Kaldır") { service.customScreenshotFolder = nil }
                }
                Button("Seç…") { chooseFolder() }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Klasörü İzle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        service.customScreenshotFolder = url.path
    }

    nonisolated static func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
