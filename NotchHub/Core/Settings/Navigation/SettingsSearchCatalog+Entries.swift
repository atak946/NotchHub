// Search terms for each settings page: section titles and control labels (Turkish key + English
// translation from Localizable.xcstrings) plus synonyms. Keep in sync with the pages in SettingsPages*.swift.
extension SettingsSearchCatalog {
    static let general = SettingsSearchEntry(
        category: .general,
        title: SettingsSearchTerm("Genel", "General"),
        items: [
            SettingsSearchTerm("Girişte başlat", "Launch at Login"),
            SettingsSearchTerm("NotchHub'ı Duraklat", "Pause NotchHub"),
            SettingsSearchTerm("Dil", "Language"),
            SettingsSearchTerm("Güncellemeler", "Updates"),
            SettingsSearchTerm("Otomatik olarak denetle", "Automatically Check"),
            SettingsSearchTerm("Otomatik indir ve kur", "Automatically Download and Install"),
            SettingsSearchTerm("Sürüm", "Version"),
            SettingsSearchTerm("Şimdi denetle", "Check Now"),
            SettingsSearchTerm("Destek", "Support"),
            SettingsSearchTerm("Kurulum sihirbazı…", "Setup Assistant…"),
            SettingsSearchTerm("Sorun bildir…", "Report an Issue…"),
        ],
        synonyms: ["başlangıç", "oturum açma", "login", "startup", "language", "türkçe", "english", "güncelleme", "update", "version", "duraklat", "pause", "yardım", "help", "onboarding"]
    )

    static let notch = SettingsSearchEntry(
        category: .notch,
        title: SettingsSearchTerm("Çentik ve Görünüm", "Notch & Appearance"),
        items: [
            SettingsSearchTerm("Davranış", "Behavior"),
            SettingsSearchTerm("Üzerine gelme gecikmesi", "Hover Delay"),
            SettingsSearchTerm("Uygulama tam ekranken gizle", "Hide When an App Is Full Screen"),
            SettingsSearchTerm("Ekranlar", "Displays"),
            SettingsSearchTerm("Gösterilecek ekran", "Display"),
            SettingsSearchTerm("Çentiği olmayan ekranlarda sanal çentik", "Virtual Notch on Displays Without One"),
            SettingsSearchTerm("Görünüm", "Appearance"),
            SettingsSearchTerm("Tema", "Theme"),
            SettingsSearchTerm("Panel Sekmeleri", "Panel Tabs"),
        ],
        synonyms: ["çentik", "notch", "hover", "gecikme", "delay", "tam ekran", "fullscreen", "monitör", "monitor", "display", "harici ekran", "external display", "koyu", "dark", "theme", "sekme", "tab", "modül", "module"]
    )

    static let hud = SettingsSearchEntry(
        category: .hud,
        title: SettingsSearchTerm("Sistem HUD'u", "System HUD"),
        items: [
            SettingsSearchTerm("Göstergeler", "Indicators"),
            SettingsSearchTerm("Ses/parlaklık göstergesi çentikte", "Volume/Brightness HUD in Notch"),
            SettingsSearchTerm("macOS ses/parlaklık kutusunu gizle (tuşları NotchHub yönetir)", "Hide macOS Volume/Brightness HUD (NotchHub handles the keys)"),
        ],
        synonyms: ["hud", "ses", "volume", "parlaklık", "brightness", "klavye tuşları", "keyboard keys", "osd"]
    )

    static let alerts = SettingsSearchEntry(
        category: .alerts,
        title: SettingsSearchTerm("Uyarılar", "Alerts"),
        items: [
            SettingsSearchTerm("Çentik Uyarıları", "Notch Alerts"),
            SettingsSearchTerm("Çentikten animasyonlu uyarılar", "Animated alerts from the notch"),
            SettingsSearchTerm("Parça değişimlerini göster", "Show Track Changes"),
        ],
        synonyms: ["uyarı", "alert", "banner", "animasyon", "animation", "şarkı değişimi", "track change"]
    )

    static let shelf = SettingsSearchEntry(
        category: .shelf,
        title: SettingsSearchTerm("Raf ve Pano", "Shelf & Clipboard"),
        items: [
            SettingsSearchTerm("Dosya Rafı", "File Shelf"),
            SettingsSearchTerm("Öğeleri otomatik kaldır", "Remove Items Automatically"),
            SettingsSearchTerm("Pano Geçmişi", "Clipboard History"),
            SettingsSearchTerm("Geçmişi temizle", "Clear history"),
        ],
        synonyms: ["raf", "shelf", "dosya", "file", "pano", "clipboard", "kopyala", "copy", "yapıştır", "paste", "sürükle", "drag"]
    )

    static let media = SettingsSearchEntry(
        category: .media,
        title: SettingsSearchTerm("Medya", "Media"),
        items: [
            SettingsSearchTerm("Kapalıyken medya kontrolleri", "Media Controls When Closed"),
            SettingsSearchTerm("Müzik dalgası", "Music visualizer"),
        ],
        synonyms: ["müzik", "music", "spotify", "apple music", "şarkı", "song", "görselleştirici", "visualizer", "ekolayzır", "equalizer", "oynat", "play", "şimdi çalıyor", "now playing"]
    )

    static let timer = SettingsSearchEntry(
        category: .timer,
        title: SettingsSearchTerm("Zamanlayıcı", "Timer"),
        items: [
            SettingsSearchTerm("Odak", "Focus"),
            SettingsSearchTerm("Kısa mola", "Short break"),
            SettingsSearchTerm("Uzun mola", "Long break"),
            SettingsSearchTerm("Uzun molaya kadar oturum", "Sessions Until Long Break"),
            SettingsSearchTerm("Sonraki aşamayı otomatik başlat", "Auto-Start Next Phase"),
        ],
        synonyms: ["pomodoro", "mola", "break", "sayaç", "countdown", "focus"]
    )

    static let calendar = SettingsSearchEntry(
        category: .calendar,
        title: SettingsSearchTerm("Takvim", "Calendar"),
        items: [
            SettingsSearchTerm("Sıradaki Toplantı", "Next Meeting"),
            SettingsSearchTerm("Hatırlatıcı", "Reminder"),
            SettingsSearchTerm("Bugünün etkinliklerini grupla", "Group Today's Events"),
            SettingsSearchTerm("Kaynaklar", "Sources"),
            SettingsSearchTerm("macOS Takvim", "macOS Calendar"),
            SettingsSearchTerm("İnternet Hesapları'nı Aç", "Open Internet Accounts"),
            SettingsSearchTerm("ICS Takvim Akışları", "ICS Calendar Feeds"),
            SettingsSearchTerm("Microsoft 365", "Microsoft 365"),
            SettingsSearchTerm("Takvimler", "Calendars"),
        ],
        synonyms: ["ics", "webcal", "outlook", "exchange", "google", "icloud", "etkinlik", "event", "toplantı hatırlatıcısı", "meeting reminder", "abonelik", "subscription"]
    )

    static let notes = SettingsSearchEntry(
        category: .notes,
        title: SettingsSearchTerm("Notlar ve Hesap", "Notes & Calculator"),
        items: [
            SettingsSearchTerm("Notlar", "Notes"),
            SettingsSearchTerm("Hızlı hesap", "Quick calculation"),
            SettingsSearchTerm("Not sayısı", "Note Count"),
            SettingsSearchTerm("Konum", "Location"),
            SettingsSearchTerm("Finder'da Göster", "Show in Finder"),
        ],
        synonyms: ["not", "note", "hesap makinesi", "calculator", "döviz", "currency", "kur", "exchange rate", "birim", "unit"]
    )

    static let weather = SettingsSearchEntry(
        category: .weather,
        title: SettingsSearchTerm("Hava Durumu", "Weather"),
        items: [
            SettingsSearchTerm("Hava durumu", "Weather"),
            SettingsSearchTerm("Konum", "Location"),
            SettingsSearchTerm("Şehir", "City"),
            SettingsSearchTerm("Şehir ara", "Search for a city"),
        ],
        synonyms: ["hava", "weather", "sıcaklık", "temperature", "şehir", "city", "open-meteo", "yağmur", "rain"]
    )

    static let battery = SettingsSearchEntry(
        category: .battery,
        title: SettingsSearchTerm("Pil", "Battery"),
        items: [
            SettingsSearchTerm("Şarj animasyonu", "Charging animation"),
            SettingsSearchTerm("Düşük pil uyarısı", "Low battery warning"),
        ],
        synonyms: ["pil", "battery", "şarj", "charging", "güç", "power", "adaptör", "adapter"]
    )

    static let notifications = SettingsSearchEntry(
        category: .notifications,
        title: SettingsSearchTerm("Bildirimler", "Notifications"),
        items: [
            SettingsSearchTerm("Bildirim yansıtma", "Notification Mirroring"),
            SettingsSearchTerm("Bildirimleri çentikte göster", "Show Notifications in the Notch"),
            SettingsSearchTerm("Mesaj içeriğini göster", "Show Message Content"),
            SettingsSearchTerm("macOS bildirimlerini gizle", "Hide macOS Notifications"),
            SettingsSearchTerm("Hangi bildirimler", "Which Notifications"),
            SettingsSearchTerm("Uygulama bazlı gizlilik", "Per-app privacy"),
            SettingsSearchTerm("Uygulama ekle", "Add app"),
            SettingsSearchTerm("Mesajlaşma uygulamaları", "Messaging Apps"),
            SettingsSearchTerm("Erişilebilirlik izni", "Accessibility Permission"),
        ],
        synonyms: ["bildirim", "notification", "whatsapp", "telegram", "signal", "imessage", "mesajlar", "messages", "slack", "discord", "teams", "gizlilik", "privacy", "banner"]
    )

    static let unread = SettingsSearchEntry(
        category: .unread,
        title: SettingsSearchTerm("Okunmamış Mesajlar", "Unread Messages"),
        items: [
            SettingsSearchTerm("Okunmamış rozetleri", "Unread Badges"),
            SettingsSearchTerm("Okunmamış rozetlerini göster", "Show Unread Badges"),
            SettingsSearchTerm("Yeni mesajlarda uyar", "Alert on New Messages"),
            SettingsSearchTerm("Kontrol aralığı", "Check Interval"),
            SettingsSearchTerm("Erişilebilirlik izni", "Accessibility Permission"),
        ],
        synonyms: ["okunmamış", "unread", "rozet", "badge", "dock", "mesaj", "message", "mail", "posta", "whatsapp", "slack"]
    )

    static let meeting = SettingsSearchEntry(
        category: .meeting,
        title: SettingsSearchTerm("Toplantı", "Meetings"),
        items: [
            SettingsSearchTerm("Toplantı Modu", "Meeting Mode"),
            SettingsSearchTerm("Toplantıları algıla", "Detect Meetings"),
            SettingsSearchTerm("Toplantılarda Spotify / Müzik'i duraklat", "Pause Spotify / Music During Meetings"),
            SettingsSearchTerm("Kamera Aynası", "Camera Mirror"),
            SettingsSearchTerm("Toplantı öncesi kamera hatırlatması", "Pre-Meeting Camera Reminder"),
            SettingsSearchTerm("Ne zaman", "When"),
            SettingsSearchTerm("Mikrofonu Sustur", "Mute Microphone"),
            SettingsSearchTerm("Mikrofon ve Kamera", "Microphone & Camera"),
            SettingsSearchTerm("Mikrofon ve kamera göstergesini göster", "Show Microphone and Camera Indicator"),
            SettingsSearchTerm("Gizlilik göstergesi", "Privacy indicator"),
            SettingsSearchTerm("Mikrofon açık kalırsa uyar", "Warn If Microphone Stays On"),
            SettingsSearchTerm("Uyarı süresi", "Alert After"),
        ],
        synonyms: ["toplantı", "meeting", "zoom", "teams", "google meet", "webex", "facetime", "kamera", "camera", "mikrofon", "microphone", "mic", "mute", "sessize al", "ayna", "mirror"]
    )

    static let network = SettingsSearchEntry(
        category: .network,
        title: SettingsSearchTerm("Ağ ve VPN", "Network & VPN"),
        items: [
            SettingsSearchTerm("Ağ", "Network"),
            SettingsSearchTerm("Ağ bağlantısını izle", "Monitor Network Connection"),
            SettingsSearchTerm("Çevrimdışı olunca / tekrar çevrimiçi olunca uyar", "Alert when going offline / back online"),
            SettingsSearchTerm("Ağ değişince uyar", "Alert When Network Changes"),
            SettingsSearchTerm("VPN", "VPN"),
            SettingsSearchTerm("VPN bağlantısını izle", "Monitor VPN Connection"),
            SettingsSearchTerm("VPN koptuğunda veya yeniden bağlandığında uyar", "Alert when the VPN disconnects or reconnects"),
            SettingsSearchTerm("Algılanan istemci", "Detected Client"),
        ],
        synonyms: ["wifi", "wi-fi", "internet", "ethernet", "network", "çevrimdışı", "offline", "tünel", "tunnel", "wireguard", "forticlient", "cisco"]
    )

    static let headphones = SettingsSearchEntry(
        category: .headphones,
        title: SettingsSearchTerm("Kulaklık", "Headphones"),
        items: [
            SettingsSearchTerm("Kulaklık bağlanınca pil durumunu göster", "Show Battery When Headphones Connect"),
        ],
        synonyms: ["airpods", "bluetooth", "headphones", "beats", "kulaklık pili", "headphone battery"]
    )

    static let performance = SettingsSearchEntry(
        category: .performance,
        title: SettingsSearchTerm("Performans", "Performance"),
        items: [
            SettingsSearchTerm("Sistem Sağlığı", "System Health"),
            SettingsSearchTerm("Bellek, sıcaklık ve diski izle", "Monitor Memory, Thermals and Disk"),
            SettingsSearchTerm("Yüksek baskıda veya düşük diskte uyar", "Alert on high pressure or low disk space"),
            SettingsSearchTerm("Düşük disk alanı eşiği", "Low Disk Space Threshold"),
        ],
        synonyms: ["bellek", "memory", "ram", "işlemci", "cpu", "sıcaklık", "thermal", "disk", "depolama", "storage", "baskı", "pressure"]
    )

    static let remoteSession = SettingsSearchEntry(
        category: .remoteSession,
        title: SettingsSearchTerm("Uzak Oturum", "Remote Session"),
        items: [
            SettingsSearchTerm("Uzak Oturum Farkındalığı", "Remote Session Awareness"),
            SettingsSearchTerm("Biri bu Mac'e bağlandığında göster", "Show When Someone Connects to This Mac"),
            SettingsSearchTerm("Oturum başlayıp bittiğinde uyar", "Alert When a Session Starts or Ends"),
            SettingsSearchTerm("Durum", "Status"),
        ],
        synonyms: ["anydesk", "ekran paylaşımı", "screen sharing", "uzaktan yönetim", "remote management", "vnc", "uzak masaüstü", "remote desktop"]
    )

    static let devOps = SettingsSearchEntry(
        category: .devOps,
        title: SettingsSearchTerm("DevOps", "DevOps"),
        items: [
            SettingsSearchTerm("Docker", "Docker"),
            SettingsSearchTerm("Container'ları izle", "Monitor Containers"),
            SettingsSearchTerm("Çökme, OOM ve sağlık değişikliklerinde uyar", "Alert on crashes, OOM and health changes"),
            SettingsSearchTerm("docker stop kaynaklı çıkışları yoksay", "Ignore exits caused by docker stop"),
            SettingsSearchTerm("Daemon", "Daemon"),
            SettingsSearchTerm("Uç Noktalar", "Endpoints"),
            SettingsSearchTerm("Uç noktaları izle", "Monitor Endpoints"),
            SettingsSearchTerm("Uç nokta kapanınca veya düzelince uyar", "Alert when an endpoint goes down or recovers"),
            SettingsSearchTerm("Uç Nokta Ekle…", "Add Endpoint…"),
            SettingsSearchTerm("Yerel LLM", "Local LLM"),
            SettingsSearchTerm("LM Studio ve Ollama'yı izle", "Monitor LM Studio and Ollama"),
            SettingsSearchTerm("Sunucu başlayınca veya durunca uyar", "Alert when the server starts or stops"),
        ],
        synonyms: ["container", "konteyner", "endpoint", "api", "http", "sağlık kontrolü", "health check", "ollama", "lm studio", "llm", "yapay zeka", "ai"]
    )

    static let profiles = SettingsSearchEntry(
        category: .profiles,
        title: SettingsSearchTerm("Profiller", "Profiles"),
        items: [
            SettingsSearchTerm("Müşteri Profilleri", "Client Profiles"),
            SettingsSearchTerm("Profil Ekle", "Add Profile"),
            SettingsSearchTerm("Çentikte profil uyarıları", "Profile Alerts in the Notch"),
            SettingsSearchTerm("Terminal uygulaması bundle ID", "Terminal App Bundle ID"),
            SettingsSearchTerm("VPN uygulaması", "VPN App"),
            SettingsSearchTerm("Çalışma klasöründen öneriler", "Suggestions from Working Directory"),
        ],
        synonyms: ["profil", "profile", "müşteri", "client", "çalışma alanı", "workspace", "terminal", "proje", "project"]
    )

    static let integrations = SettingsSearchEntry(
        category: .integrations,
        title: SettingsSearchTerm("Entegrasyonlar", "Integrations"),
        items: [
            SettingsSearchTerm("Betiklerden ve uygulamalardan gelen uyarıları kabul et", "Accept Alerts from Scripts and Apps"),
            SettingsSearchTerm("Web/URL üzerinden uyarılara izin ver", "Allow Alerts via Web/URL"),
            SettingsSearchTerm("Yerel soket", "Local socket"),
            SettingsSearchTerm("Soket yolu", "Socket Path"),
            SettingsSearchTerm("Uzun komut eşiği", "Long Command Threshold"),
            SettingsSearchTerm("zsh kurulum satırını kopyala", "Copy zsh Setup Line"),
            SettingsSearchTerm("Test uyarısı gönder", "Send Test Alert"),
        ],
        synonyms: ["zsh", "shell", "kabuk", "cli", "komut satırı", "command line", "soket", "socket", "url scheme", "betik", "script", "webhook"]
    )

    static let shortcuts = SettingsSearchEntry(
        category: .shortcuts,
        title: SettingsSearchTerm("Kestirmeler", "Shortcuts"),
        items: [
            SettingsSearchTerm("Klavye kısayolları", "Keyboard Shortcuts"),
            SettingsSearchTerm("Paneli aç/kapat", "Toggle Panel"),
            SettingsSearchTerm("Mikrofonu sustur/aç", "Mute/Unmute Microphone"),
            SettingsSearchTerm("Kestirmeler uygulaması", "Shortcuts App"),
            SettingsSearchTerm("Kestirmeler'i Aç", "Open Shortcuts"),
        ],
        synonyms: ["kısayol", "shortcut", "hotkey", "klavye", "keyboard", "siri", "app intents", "eylem", "action"]
    )

    static let automations = SettingsSearchEntry(
        category: .automations,
        title: SettingsSearchTerm("Otomasyonlar", "Automations"),
        items: [
            SettingsSearchTerm("Odak Koruma", "Focus Guard"),
            SettingsSearchTerm("Odak sırasında dikkat dağıtan bir uygulama açtığımda hatırlat", "Remind Me When I Open a Distracting App During Focus"),
            SettingsSearchTerm("Aynı uygulama için şu süre içinde tekrarlama", "Don't Repeat for the Same App Within"),
            SettingsSearchTerm("Ekran Görüntüleri ve İndirilenler", "Screenshots and Downloads"),
            SettingsSearchTerm("Yeni ekran görüntülerini ve indirilenleri rafa öner", "Suggest New Screenshots and Downloads for the Shelf"),
            SettingsSearchTerm("Ekran görüntülerini izle", "Watch Screenshots"),
            SettingsSearchTerm("Ekran görüntülerini rafa otomatik ekle", "Add Screenshots to Shelf Automatically"),
            SettingsSearchTerm("İndirilenleri izle", "Watch Downloads"),
            SettingsSearchTerm("Alt klasörleri dahil et", "Include Subfolders"),
            SettingsSearchTerm("Ekran görüntüsü klasörü", "Screenshot Folder"),
            SettingsSearchTerm("Ek klasör", "Additional Folder"),
        ],
        synonyms: ["otomasyon", "automation", "screenshot", "ekran görüntüsü", "downloads", "indirilenler", "shottr", "dikkat dağıtıcı", "distraction", "odak koruma", "focus guard"]
    )

    static let timeTracking = SettingsSearchEntry(
        category: .timeTracking,
        title: SettingsSearchTerm("Zaman Takibi", "Time Tracking"),
        items: [
            SettingsSearchTerm("Zaman takibi", "Time Tracking"),
            SettingsSearchTerm("Faturalanabilir zamanı takip et", "Track Billable Time"),
            SettingsSearchTerm("Boşta kalınca duraklat", "Pause When Idle"),
            SettingsSearchTerm("Hafta içi özet hatırlatıcısı", "Weekday Summary Reminder"),
            SettingsSearchTerm("Hatırlatma saati", "Reminder Time"),
            SettingsSearchTerm("Takip kuralları", "Tracking Rules"),
            SettingsSearchTerm("Kural ekle", "Add Rule"),
            SettingsSearchTerm("Takip verileri", "Tracking Data"),
            SettingsSearchTerm("Haftayı CSV olarak dışa aktar…", "Export Week as CSV…"),
            SettingsSearchTerm("Verileri sıfırla…", "Reset Data…"),
            SettingsSearchTerm("Erişilebilirlik izni", "Accessibility Permission"),
        ],
        synonyms: ["zaman", "time", "fatura", "billing", "billable", "csv", "timesheet", "mesai", "saat", "hours"]
    )
}
