import SwiftUI

struct CameraMirrorSettingsSection: View {
    @Bindable var reminder: CameraReminderService

    var body: some View {
        Section("Kamera Aynası") {
            Toggle("Toplantı öncesi kamera hatırlatması", isOn: $reminder.isEnabled)
            Picker("Ne zaman", selection: $reminder.leadTime) {
                ForEach(CameraReminderPolicy.leadTimeOptions, id: \.self) { lead in
                    Text("\(Int(lead / 60)) dk önce").tag(lead)
                }
            }
            .disabled(!reminder.isEnabled)
            Text("Görüntülü toplantılardan önce çentikte uyarı gösterir. Kamera yalnızca \"Kamerayı kontrol et\" veya \"Ayna\" tıklanınca açılır ve 60 sn sonra kapanır.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
