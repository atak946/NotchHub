import Foundation

extension SettingsCategory {
    /// One line under the page title describing what the page holds.
    var subtitle: LocalizedStringResource {
        switch self {
        case .general: "Dil, başlangıç, güncellemeler ve destek."
        case .notch: "Çentiğin davranışı, ekranlar, tema ve panel sekmeleri."
        case .hud: "Ses ve parlaklık göstergesi çentikte."
        case .alerts: "Çentikten çıkan animasyonlu uyarılar."
        case .shelf: "Dosya rafı ve pano geçmişi."
        case .media: "Kapalı çentikte medya kontrolleri ve müzik dalgası."
        case .timer: "Pomodoro süreleri ve aşama geçişleri."
        case .calendar: "Toplantı hatırlatıcısı, takvim kaynakları ve görünen takvimler."
        case .notes: "Notlar ve hızlı hesap."
        case .weather: "Konum ve hava durumu kaynağı."
        case .battery: "Şarj animasyonu ve düşük pil uyarıları."
        case .notifications: "Bildirimleri çentikte göster, içeriği uygulama bazında gizle."
        case .unread: "Dock rozetlerinden okunmamış mesaj sayıları."
        case .meeting: "Toplantı modu, kamera aynası, mikrofon ve gizlilik göstergesi."
        case .network: "Bağlantı ve VPN durumunu izle."
        case .headphones: "Bluetooth kulaklık pil seviyeleri."
        case .performance: "Bellek, sıcaklık ve disk alanı uyarıları."
        case .remoteSession: "Biri bu Mac'e uzaktan bağlandığında haber ver."
        case .devOps: "Docker, uç noktalar ve yerel LLM sunucuları."
        case .profiles: "Müşteri profilleri ve çalışma klasörü önerileri."
        case .integrations: "Betiklerden, terminalden ve URL'lerden gelen uyarılar."
        case .shortcuts: "Klavye kısayolları ve Kestirmeler eylemleri."
        case .automations: "Odak koruma, ekran görüntüleri ve indirilenler."
        case .timeTracking: "Faturalanabilir zaman, takip kuralları ve dışa aktarma."
        }
    }
}
