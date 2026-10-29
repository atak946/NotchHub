# NotchHub — Özellik Listesi

Ekrandaki çentiği (notch) etkileşimli bir panele dönüştüren hafif bir menü çubuğu uygulaması.
Fare çentiğe gelince panel aşağı doğru genişler; uzaklaşınca kapanır.

**Hedef:** macOS 26+, Swift 6, SwiftUI + AppKit (`NSPanel`), Dock ikonu yok (`LSUIElement`).

---

## 1. Çekirdek — Çentik Paneli

| Özellik | Açıklama | Faz |
|---|---|---|
| Çentik algılama | `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` ile çentik konumu ve boyutu | MVP |
| Hover ile açılma | Fare çentik bölgesine girince ~150 ms gecikmeyle panel açılır | MVP |
| Kapanma | Fare panelden çıkınca veya `Esc` ile kapanır | MVP |
| Animasyon | Çentikten "akarak" büyüyen yay (spring) animasyonu, yalnızca transform/opacity | MVP |
| Kompakt mod | Panel kapalıyken çentiğin iki yanında küçük göstergeler (çalan şarkı kapağı, kalan süre) | MVP |
| Çentiksiz ekran | Harici monitörde üst ortada sanal çentik | MVP |
| Çoklu ekran | Aktif ekranı takip et veya sabit ekran seç | MVP |
| Tam ekran davranışı | Tam ekran uygulamada otomatik gizlen (ayarlanabilir) | MVP |

## 2. Dosya Rafı (Shelf)

| Özellik | Açıklama | Faz |
|---|---|---|
| Sürükle-bırak | Dosyayı çentiğe sürükleyince panel açılır ve dosya rafa bırakılır | MVP |
| Raftan sürükle | Raftaki dosya başka uygulamaya veya klasöre sürüklenebilir | MVP |
| Çoklu dosya | Birden fazla dosyayı tek seferde taşı | MVP |
| Önizleme | Küçük resim (QuickLook thumbnail), `Space` ile Quick Look | MVP |
| Hızlı aksiyonlar | AirDrop, Finder'da göster, kopyala, raftan kaldır | MVP |
| Metin/görsel | Panodan veya sürüklenen metin/görsel parçacıkları da rafa | MVP |
| Kalıcılık | Raf yeniden başlatmada korunur (security-scoped bookmark) | MVP |
| Otomatik temizlik | X saat sonra raftan otomatik kaldır (ayar) | MVP |

## 3. Medya — Çalan Şarkı

| Özellik | Açıklama | Faz |
|---|---|---|
| Şarkı bilgisi | Kapak, şarkı, sanatçı | MVP |
| Kontroller | Oynat/duraklat, önceki, sonraki | MVP |
| İlerleme çubuğu | Süre + sürükleyerek konum değiştirme | MVP |
| Kaynaklar | Spotify ve Apple Music (AppleScript / ScriptingBridge) | MVP |
| Ses çıkışı | AirPods / hoparlör arasında hızlı geçiş | MVP |

> ⚠️ macOS 15.4+ üçüncü parti uygulamaların özel `MediaRemote` framework'ünü kullanmasını kısıtladı.
> Bu yüzden MVP'de uygulamaya özel AppleScript köprüsü kullanılacak (Spotify, Music).

## 4. Zamanlayıcı

| Özellik | Açıklama | Faz |
|---|---|---|
| Hızlı zamanlayıcı | 5 / 15 / 25 / 45 dk ön ayarları + özel süre | MVP |
| Kompakt geri sayım | Panel kapalıyken çentiğin yanında kalan süre | MVP |
| Pomodoro | Çalışma/mola döngüsü | MVP |
| Bitiş bildirimi | Ses + çentikte titreşim animasyonu + sistem bildirimi | MVP |

## 5. Takvim — Sıradaki Toplantı

| Özellik | Açıklama | Faz |
|---|---|---|
| Sıradaki etkinlik | Başlık, saat, "15 dk sonra" | MVP |
| Toplantıya katıl | Etkinlikteki Zoom / Teams / Meet linkini algıla, tek tıkla aç | MVP |
| Hatırlatma | Toplantıdan 5 dk önce çentik kendiliğinden açılır | MVP |
| Bugünün özeti | Günün kalan etkinlikleri listesi | MVP |
| Kaynak | EventKit (Outlook/Google hesabı macOS Takvim'e ekli olmalı) | MVP |

### Takvim — Hesap ve uygulama gruplama

| Özellik | Açıklama | Faz |
|---|---|---|
| Tüm hesaplar | Outlook (Exchange/Office 365), Google, iCloud — macOS İnternet Hesapları üzerinden EventKit | MVP |
| Hesaba göre grupla | Bugünün etkinlikleri Outlook / Google / iCloud başlıkları altında | MVP |
| Uygulamaya göre grupla | Zoom / Teams / Meet / Webex / linksiz | MVP |
| Takvim filtreleri | Ayarlardan takvim bazında göster/gizle (hatırlatmalar da uyar) | MVP |

## 6. Animasyonlu Çentik Uyarıları

| Özellik | Açıklama | Faz |
|---|---|---|
| Uyarı bandı | Zamanı gelen olayda çentik yayla genişler; ikon, başlık, alt başlık, aksiyon | MVP |
| Dikkat animasyonu | Titreme (shake), ikon zıplaması, renkli nabız halkası ve kenar parıltısı | MVP |
| Toplantı hatırlatması | X dk önce "Join" butonlu turuncu uyarı, tıklanana kadar kalır | MVP |
| Zamanlayıcı bitti | Yeşil uyarı + Pomodoro faz değişimi | MVP |
| Şarkı değişti | Kısa (3 sn) bilgi bandı, aynı türdekiler birbirini değiştirir | MVP |
| Kuyruk | Birden fazla uyarı sırayla gösterilir; üzerine gelince otomatik kapanma durur | MVP |
| Panel açıkken | İlgili sekmeye geçer ve panel titrer | MVP |

### Takvim — Yeni Outlook kaynakları

| Özellik | Açıklama | Faz |
|---|---|---|
| ICS feed | Outlook web → Ayarlar → Takvim → Paylaşılan takvimler → Yayımla → ICS linki (Keychain'de saklanır) | v1.1 |
| Microsoft 365 | Device code ile giriş, Graph `calendarView` (kendi Azure uygulama kaydın gerekir) | v1.1 |
| Kaynak teşhisi | Kaynak başına "bugün N etkinlik" | v1.1 |

## 7. Notlar (v1.2)

| Özellik | Açıklama | Faz |
|---|---|---|
| Not listesi + düzenleyici | Solda notlar (sabitlenenler önce, sonra en son düzenlenen), sağda düz metin düzenleyici | v1.2 |
| Toplantı/müşteri bağlamı | Devam eden toplantı sırasında açılan not toplantı başlığını, aktif müşteri profili müşteri adını alır | v1.2 |
| Başlık | İlk dolu satır; boş toplantı notunda "Toplantı: <başlık> · <saat>" | v1.2 |
| Kontrol listesi | `[ ] ` / `[x] ` satırları önizlemede tıklanabilir kutucuk olur, tıklayınca satır güncellenir | v1.2 |
| Müşteri filtresi | Müşterili not varsa liste üstünde müşteri çipleri | v1.2 |
| Silme | Satır içinde "Silinsin mi?" onayı (modal yok) | v1.2 |
| Dışa aktarma | Notu `.md` dosyası olarak sürükle, "Rafa ekle" ile rafa koy, "Kopyala" ile panoya al | v1.2 |
| Klavye | Düzenleyiciye tıklayınca panel klavye odağını alır; yazarken fare çıkınca kapanmaz, `Esc` kapatır | v1.2 |
| Saklama | `~/Library/Application Support/NotchHub/notes.json`, atomik ve gecikmeli (debounce) yazma; yalnızca yerel, eşitleme yok | v1.2 |

## 8. Status sekmesi ve izleyiciler (v1.1)

Mikrofon/kamera, VPN, ağ, sistem baskısı, toplantı modu, Docker/OrbStack, endpoint + SSL, LM Studio/Ollama,
odak bekçisi, ekran görüntüsü/indirme yakalayıcı, okunmamış rozetleri, zaman takibi, müşteri profilleri,
uzak oturum göstergesi, `notchhub://` API + socket + CLI + zsh/Xcode build hook'ları. Ayrıntı: `docs/IDEAS.md`.

### Bildirim yansıtma (v1.2)

macOS bildirim bantları Erişilebilirlik API'si ile Bildirim Merkezi'nden okunur ve çentikte gösterilir.

| Özellik | Açıklama | Faz |
|---|---|---|
| Çentik uyarısı | Mesajlaşma uygulamalarında başlık gönderici ("Ahmet Yılmaz"), alt başlık "WhatsApp · <mesaj, ~80 karakter>"; diğer uygulamalarda bildirim başlığı ve "<Uygulama> · <alt başlık veya metin>". "Aç" uygulamayı öne getirir | v1.2 |
| Grup mesajları | Gövde "Ad: mesaj" biçimindeyse başlık "Ahmet · Proje Grubu" olur | v1.2 |
| macOS bildirimlerini gizle | Yansıtılan bant Bildirim Merkezi'nin "Kapat" eylemiyle kapatılır (varsayılan açık); bant kapanmadan önce kısa bir an görünebilir | v1.2 |
| Hangi bildirimler | "Tüm uygulamalar" (varsayılan) veya "Yalnızca mesajlaşma uygulamaları" (whatsapp, zoom, teams, outlook, slack; düzenlenebilir, büyük/küçük harf duyarsız "içerir" eşleşmesi) | v1.2 |
| Mesaj içeriğini göster | Kapalıyken alt başlık "WhatsApp · Yeni mesaj" olur | v1.2 |
| Gecikme | AXObserver olayı ile ~0,3 sn; yedek olarak bant varken 250 ms, yokken 1 sn yoklama | v1.2 |
| Güvenlik | NotchHub'ın kendi bildirimlerine dokunulmaz; çentik uyarıları kapalıyken veya duraklatılmışken hiçbir bildirim kapatılmaz; açılışta ekrandaki bant yeniden gösterilmez | v1.2 |
| Rozet uyarısıyla çakışma | Aynı uygulama için son 15 sn içinde yansıtılan bildirim varsa Dock rozetinin "· 1 yeni" uyarısı atlanır (Odak/Rahatsız Etme bantları gizlediğinde rozet uyarısı yine gelir) | v1.2 |
| Status kutucuğu | Okunmamış kutucuğunda "Son: <gönderici> · <uygulama>" satırı | v1.2 |

## 9. Ayarlar

| Özellik | Açıklama | Faz |
|---|---|---|
| Menü çubuğu ikonu | Ayarlar, duraklat, çıkış | MVP |
| Modül aç/kapa | Raf, medya, zamanlayıcı, takvim, notlar tek tek açılıp kapatılır | MVP |
| Girişte başlat | `SMAppService` ile | MVP |
| Hover gecikmesi | Açılma gecikmesi ve hassasiyet ayarı | MVP |
| Kısayol | Paneli klavyeyle aç (ör. `⌥⌘N`) | MVP |
| Tema | Sistem / koyu (çentik siyah olduğu için varsayılan koyu) | MVP |

---

## Fazlar

Tüm özellikler **v1.0** kapsamında. Geliştirme sırası (her adım çalışır durumda teslim edilir):

1. **Çekirdek:** Çentik paneli, hover/kapanma, animasyon, çentiksiz ekran, çoklu ekran, tam ekran davranışı, menü çubuğu, ayarlar
2. **Dosya rafı:** Sürükle-bırak, önizleme, hızlı aksiyonlar, kalıcılık, pano parçacıkları, otomatik temizlik
3. **Medya:** Spotify/Music bilgisi ve kontrolleri, ilerleme çubuğu, ses çıkışı geçişi
4. **Zamanlayıcı:** Ön ayarlar, Pomodoro, bildirim
5. **Takvim:** Sıradaki toplantı, toplantıya katıl, 5 dk önce hatırlatma, günün özeti
6. **Kompakt mod:** Panel kapalıyken şarkı kapağı ve geri sayım göstergeleri
7. **Uyarılar:** Animasyonlu çentik uyarıları ve takvim gruplama

## Kapsam Dışı (şimdilik)

- Hava durumu, pil, widget mağazası
- iCloud senkronizasyonu
- App Store dağıtımı (sandbox kısıtları nedeniyle önce doğrudan `.app` / notarize)

## İzinler

| İzin | Neden |
|---|---|
| Takvim (EventKit) | Sıradaki toplantı |
| Otomasyon (Apple Events) | Spotify / Music kontrolü |
| Bildirimler | Zamanlayıcı ve toplantı uyarısı |
| Erişilebilirlik | Dock rozetleri, pencere başlıkları ve bildirim yansıtma (Bildirim Merkezi bantlarını okuma/kapatma) |

## Mimari Taslağı

```
NotchHub/
├── App/                 # NotchHubApp, AppDelegate, menü çubuğu
├── Core/
│   ├── Notch/           # NotchPanel (NSPanel), NotchGeometry, HoverTracker
│   └── Settings/        # SettingsStore (@AppStorage)
├── Features/
│   ├── Shelf/           # ShelfView, ShelfStore, ShelfItem
│   ├── Media/           # MediaView, MediaService protocol, SpotifyProvider, MusicProvider
│   ├── Timer/           # TimerView, TimerService
│   └── Calendar/        # NextEventView, CalendarService (EventKit), MeetingLinkParser
└── Tests/               # Geometri, MeetingLinkParser, TimerService, ShelfStore unit testleri
```

Her modül bir protokol arkasında (`MediaService`, `CalendarService` …) → test için mock'lanabilir.
