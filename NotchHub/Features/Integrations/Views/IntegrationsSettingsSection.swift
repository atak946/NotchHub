import SwiftUI

/// `Section("Entegrasyonlar")` for the grouped settings Form: socket status, zsh setup and a test alert.
struct IntegrationsSettingsSection: View {
    private static let copiedFeedback: Duration = .seconds(2)

    @Bindable private var service: ExternalAlertService
    @State private var didCopy = false

    init(service: ExternalAlertService) {
        self.service = service
    }

    var body: some View {
        Section("Entegrasyonlar") {
            Toggle("Betiklerden ve uygulamalardan gelen uyarıları kabul et", isOn: $service.isEnabled)
            Toggle("Web/URL üzerinden uyarılara izin ver", isOn: $service.urlAlertsEnabled)
                .disabled(!service.isEnabled)
                .help("notchhub:// bağlantılarını herhangi bir uygulama veya web sayfası açabilir. Kapalıyken yalnızca yerel soket ve komut satırı aracı kabul edilir.")

            LabeledContent("Yerel soket") {
                socketStatus
            }
            LabeledContent("Soket yolu") {
                Text(service.socketPath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Uzun komut eşiği") {
                Text("\(ExternalAlertService.defaultMinimumCommandSeconds) sn")
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(service.zshSetupLine)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                Text(setupHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(copyButtonTitle, systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                    copySetupLine()
                }
                Button("Test uyarısı gönder", systemImage: "bell.badge") {
                    service.sendTestAlert()
                }
                .disabled(!service.isEnabled)
            }
        }
    }

    @ViewBuilder
    private var socketStatus: some View {
        switch service.socketState {
        case .listening:
            Label("Dinleniyor", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .starting:
            Label("Başlatılıyor…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .stopped:
            Text(service.isEnabled ? String(localized: "Durduruldu") : String(localized: "Kapalı"))
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var copyButtonTitle: String {
        didCopy ? String(localized: "Kopyalandı") : String(localized: "zsh kurulum satırını kopyala")
    }

    private var setupHint: String {
        let location = service.isZshHookBundled
            ? String(localized: "Bu satırı ~/.zshrc dosyasına ekleyin")
            : String(localized: "Bu satırı ~/.zshrc dosyasına ekleyin, tools/Integrations/notchhub.zsh dosyasını göstersin")
        let minimumSeconds = ExternalAlertService.defaultMinimumCommandSeconds
        let environmentKey = ExternalAlertService.minimumSecondsEnvironmentKey
        let window = Int(IntegrationsRateLimiter.defaultWindow)
        let capacity = IntegrationsRateLimiter.defaultCapacity
        let urlCapacity = ExternalAlertService.urlRateLimitCapacity
        // One key so the translation keeps the sentence order.
        return String(localized: "\(location). \(minimumSeconds) sn veya daha uzun süren komutlar çentikte uyarı gösterir; değiştirmek için \(environmentKey) kullanın. \(window) sn içinde en fazla \(capacity) uyarı; URL üzerinden dakikada en fazla \(urlCapacity) uyarı.")
    }

    private func copySetupLine() {
        service.copyZshSetupLine()
        didCopy = true
        Task {
            try? await Task.sleep(for: Self.copiedFeedback)
            didCopy = false
        }
    }
}
