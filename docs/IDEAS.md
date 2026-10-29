# NotchHub — v1.1+ Fikirleri

## Hızlı kazanımlar
1. **Mikrofon / kamera göstergesi** — CoreAudio + CoreMediaIO "running somewhere"; izin gerekmez.
2. **VPN bekçisi** — NWPathMonitor + `utun*` arayüzü; bilinen istemciler (Cisco, GlobalProtect, FortiClient, WireGuard, Tailscale…) algılanır; "VPN düştü" uyarısı.
3. **Ağ değişimi / çevrimdışı** — NWPathMonitor; SSID için Konum izni gerekir.
4. **Sistem baskısı** — bellek baskısı ve ısınma uyarısı (ör. yerel LLM + Docker + Xcode birlikte çalışırken).
5. **Odak bekçisi** — Pomodoro sırasında WhatsApp/Notion öne gelince çentik titrer.
6. **Ekran görüntüsü / indirme yakalayıcı** — yeni dosya küçük resimle bant olarak çıkar, tek tıkla rafa.

## Orta
7. **Harici uyarı API'si** — `notchhub://alert?...` + CLI; her script çentiğe uyarı gönderebilir.
8. **Build / uzun komut bitti** — zsh hook + Xcode Behaviors → yeşil/kırmızı uyarı, süre, çıkış kodu.
9. **Docker / OrbStack izleyici** — docker.sock events; container die/unhealthy/OOM uyarısı.
10. **Endpoint sağlık izleyici** — staging/localhost up/down + SSL sertifika bitiş uyarısı.
11. **Okunmamış rozetleri** — Dock AX üzerinden Outlook/WhatsApp sayısı (Erişilebilirlik izni).
12. **Toplantı modu** — Zoom + mikrofon aktifken süre, Spotify otomatik durur/devam eder.
13. **Yerel LLM durumu** — LM Studio sunucusu/model durumu.

## İddialı
14. **Müşteri bağlam profilleri** — tek tıkla VPN + endpoint + docker compose + VS Code + RDM.
15. **Faturalanabilir zaman takibi** — uygulama/pencere → müşteri bazında otomatik saat.
16. **Uzak oturum farkındalığı** — AnyDesk/RDM bağlıyken kalıcı gösterge (heuristik, riskli).

## Mümkün olmayanlar
- Diğer uygulamaların bildirim içeriğini okumak (özel API / korumalı veritabanı).
- Zoom'un kendi mute durumunu güvenilir okumak.

## Önerilen v1.1 ilk 5
7 (Harici API) → 8 (Build bitti) → 1+12 (Mikrofon + Toplantı modu) → 2 (VPN bekçisi) → 9 (Docker izleyici)
