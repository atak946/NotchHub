import AppKit
import SwiftUI

/// Microsoft 365 sign-in (device code flow) with the user's own Azure app registration.
struct MicrosoftAccountSettingsSection: View {
    @Bindable private var source: MicrosoftGraphSource

    init(source: MicrosoftGraphSource) {
        self.source = source
    }

    var body: some View {
        Section {
            TextField("Uygulama (istemci) kimliği", text: $source.clientID, prompt: Text("00000000-0000-0000-0000-000000000000"))
                .disabled(isBusyOrSignedIn)
            TextField("Kiracı", text: $source.tenant, prompt: Text(MicrosoftGraphConfiguration.defaultTenant))
                .disabled(isBusyOrSignedIn)
            DisclosureGroup("Kurulum talimatları") {
                Text(Self.instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            stateContent
            if let message = source.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Microsoft 365")
        }
    }

    private static let instructions = """
    1. portal.azure.com › Microsoft Entra ID › Uygulama kayıtları › Yeni kayıt (herhangi bir ad, \
    "Herhangi bir kuruluş dizinindeki hesaplar").
    2. Kimlik doğrulama › Gelişmiş ayarlar › Genel istemci akışlarına izin ver › Evet.
    3. API izinleri › Ekle › Microsoft Graph › Temsilci › Calendars.Read (User.Read varsayılan olarak eklenir). \
    Yöneticinizin onay vermesi gerekebilir.
    4. Uygulama (istemci) kimliğini buraya kopyalayın. Kiracı: dizin kimliğiniz veya alan adınız ya da "organizations".
    """

    private var isBusyOrSignedIn: Bool {
        source.state != .signedOut
    }

    @ViewBuilder
    private var stateContent: some View {
        switch source.state {
        case .signedOut:
            Button("Microsoft ile Giriş Yap") { source.signIn() }
                .disabled(source.configuration == nil)
        case .requestingCode:
            HStack {
                ProgressView().controlSize(.small)
                Text("Giriş kodu isteniyor…").foregroundStyle(.secondary)
                Spacer()
                Button("İptal") { source.cancelSignIn() }
            }
        case let .awaitingUser(prompt):
            DeviceCodePromptView(prompt: prompt, onCancel: { source.cancelSignIn() })
        case let .signedIn(username):
            HStack {
                Label(username, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                if source.isSyncing { ProgressView().controlSize(.small) }
                Button("Yenile") { Task { await source.refreshNow() } }
                    .disabled(source.isSyncing)
                Button("Çıkış Yap") { source.signOut() }
            }
            if let lastSync = source.lastSync {
                Text("Eşitlendi: \(lastSync.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DeviceCodePromptView: View {
    let prompt: MicrosoftDeviceCodePrompt
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bu kodu şuraya girin: \(prompt.verificationURL.host() ?? "microsoft.com")")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(prompt.userCode)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                ProgressView().controlSize(.small)
                Button("Kopyala ve Aç") { copyAndOpen() }
                    .keyboardShortcut(.defaultAction)
                Button("İptal", action: onCancel)
            }
            Text("Girişi tamamlamanız bekleniyor…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func copyAndOpen() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt.userCode, forType: .string)
        NSWorkspace.shared.open(prompt.verificationURL)
    }
}
