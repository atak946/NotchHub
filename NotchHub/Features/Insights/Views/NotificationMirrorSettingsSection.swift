import SwiftUI

/// "Bildirim yansıtma": mirror macOS banners into the notch and optionally hide the native ones.
struct NotificationMirrorSettingsSection: View {
    @Bindable var mirror: NotificationMirrorService
    @State private var newKeyword = ""

    var body: some View {
        Section("Bildirim yansıtma") {
            Toggle("Bildirimleri çentikte göster", isOn: $mirror.isEnabled)
            Group {
                Toggle("Mesaj içeriğini göster", isOn: $mirror.showsMessageText)
                Toggle("macOS bildirimlerini gizle", isOn: $mirror.hidesNativeBanners)
                Picker("Hangi bildirimler", selection: $mirror.scope) {
                    ForEach(NotificationMirrorScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
            }
            .disabled(!mirror.isEnabled)
            Text("Bildirim Merkezi'ni okumak ve bildirimleri kapatmak için Erişilebilirlik izni gerekir. Odak veya Rahatsız Etme modunun gizlediği bildirimler okunamaz; macOS bildirimi kapanmadan önce kısa bir an görünebilir. Çentik uyarıları kapalıyken veya duraklatılmışken macOS bildirimlerine dokunulmaz.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Mesajlaşma uygulamaları") {
            ForEach(mirror.keywords, id: \.self) { keyword in
                HStack {
                    Text(keyword)
                    Spacer()
                    Button(role: .destructive) {
                        mirror.removeKeyword(keyword)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("\(keyword) eşleşmesini kaldır")
                }
            }
            HStack {
                TextField("Uygulama adında geçen sözcük", text: $newKeyword)
                    .onSubmit(addKeyword)
                Button("Ekle", action: addKeyword)
                    .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Eşleşen uygulamalarda başlık göndericiyi gösterir (grup mesajlarında “Ahmet · Proje Grubu”). Büyük/küçük harf fark etmez; “zoom” hem zoom.us hem Zoom Workplace ile eşleşir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!mirror.isEnabled)
    }

    private func addKeyword() {
        mirror.addKeyword(newKeyword)
        newKeyword = ""
    }
}
