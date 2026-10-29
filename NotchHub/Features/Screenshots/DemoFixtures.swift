import Foundation

/// Static, made-up content for the README screenshots. Nothing here may come from the running
/// machine (calendars, players, notifications, user or host names, paths); `DemoFixturesTests` checks that.
/// Strings are localizable so the English screenshot set shows English demo content.
enum DemoFixtures {
    // MARK: Calendar

    struct EventSpec: Equatable, Sendable {
        let id: String
        let title: String
        /// Minutes from the render time.
        let startOffsetMinutes: Int
        let durationMinutes: Int
        let location: String?
        let provider: MeetingProvider?
        let color: CalendarColor
    }

    static let accountID = "demo-account"
    static let calendarID = "demo-work"
    static var calendarTitle: String { String(localized: "İş") }
    /// Placeholder meeting URL on the reserved documentation domain.
    static let meetingURL = URL(string: "https://example.com/meeting")

    static var events: [EventSpec] {
        [
            EventSpec(
                id: "demo-sprint", title: String(localized: "Sprint planlama"), startOffsetMinutes: 12,
                durationMinutes: 45, location: nil, provider: .zoom,
                color: CalendarColor(red: 0.36, green: 0.55, blue: 1.0)
            ),
            EventSpec(
                id: "demo-design", title: String(localized: "Design review"), startOffsetMinutes: 95,
                durationMinutes: 30, location: nil, provider: .teams,
                color: CalendarColor(red: 0.69, green: 0.45, blue: 0.98)
            ),
            EventSpec(
                id: "demo-demo", title: String(localized: "Ürün demosu"), startOffsetMinutes: 180,
                durationMinutes: 60, location: String(localized: "Toplantı odası 2"), provider: nil,
                color: CalendarColor(red: 0.98, green: 0.62, blue: 0.24)
            ),
            EventSpec(
                id: "demo-retro", title: String(localized: "Haftalık retro"), startOffsetMinutes: 300,
                durationMinutes: 30, location: nil, provider: .meet,
                color: CalendarColor(red: 0.30, green: 0.80, blue: 0.55)
            ),
        ]
    }

    // MARK: Media

    struct TrackSpec: Equatable, Sendable {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let position: TimeInterval
        let artworkID: String
    }

    static let track = TrackSpec(
        title: "Midnight Drive",
        artist: "Neon Harbor",
        album: "Coastal Lights",
        duration: 214,
        position: 81,
        artworkID: "demo-artwork"
    )

    // MARK: Notes

    struct NoteSpec: Equatable, Sendable {
        let body: String
        let meetingTitle: String?
        let clientName: String?
        let isPinned: Bool
        /// Minutes before the render time.
        let ageMinutes: Int
    }

    static var notes: [NoteSpec] {
        [
            NoteSpec(
                body: String(localized: "Sprint hedefleri\n[x] Backlog'u gözden geçir\n[ ] Tahminleri güncelle\n[ ] Demo tarihini netleştir"),
                meetingTitle: String(localized: "Sprint planlama"), clientName: "Acme", isPinned: true, ageMinutes: 5
            ),
            NoteSpec(
                body: String(localized: "Fikirler\nHUD için daha yumuşak bir animasyon\nBildirimlerde hızlı yanıt"),
                meetingTitle: nil, clientName: nil, isPinned: false, ageMinutes: 90
            ),
            NoteSpec(
                body: String(localized: "Yayın kontrol listesi\n[x] Sürüm notları\n[ ] Ekran görüntüleri"),
                meetingTitle: nil, clientName: "Acme", isPinned: false, ageMinutes: 300
            ),
        ]
    }

    // MARK: Shelf

    static var shelfText: String { String(localized: "Toplantı linki: example.com/sprint") }
    /// Placeholder folders created in a temporary folder for the shelf. Folders get the stock folder icon;
    /// files would show the icon of whatever app the machine opens them with.
    static var shelfFolderNames: [String] {
        [String(localized: "Tasarım"), String(localized: "Sunum")]
    }
    static var microphoneName: String { String(localized: "Dahili mikrofon") }

    // MARK: Weather

    struct WeatherSpec: Equatable, Sendable {
        let temperature: Double
        let high: Double
        let low: Double
        let condition: WeatherCondition
        let hourlyTemperatures: [Double]
    }

    static let weather = WeatherSpec(
        temperature: 19, high: 22, low: 13, condition: .partlyCloudy,
        hourlyTemperatures: [19, 20, 21, 22, 21, 19, 17, 15]
    )

    // MARK: Alerts

    /// Messages is always installed, so the app icon resolves the same on every machine.
    static let messageAppBundleID = "com.apple.MobileSMS"
    static var messageAppName: String { String(localized: "Mesajlar") }
    static let messageSender = "Ayşe Demir"
    static var messageText: String { String(localized: "Sunumu yarın birlikte gözden geçirelim mi?") }
    static var hiddenMessagePlaceholder: String { String(localized: "İçerik gizlendi") }

    static let chargingSnapshot = PowerSnapshot(percent: 76, isPluggedIn: true, isCharging: true, minutesToFull: 42)
    static let volumeLevel = 0.62
    static let timerMinutes: TimeInterval = 25 * 60
    /// How far into the countdown the screenshots are taken.
    static let timerElapsed: TimeInterval = 9 * 60 + 24

    // MARK: Settings

    static var settingsSearchQuery: String { String(localized: "bildirim") }

    /// Every user-visible demo string, for the static-content tests.
    static var allStrings: [String] {
        var strings = [calendarTitle, shelfText, messageAppName, messageSender, messageText,
                       hiddenMessagePlaceholder, settingsSearchQuery, accountID, calendarID, messageAppBundleID]
        strings += events.flatMap { [$0.id, $0.title, $0.location ?? ""] }
        strings += [track.title, track.artist, track.album, track.artworkID]
        strings += notes.flatMap { [$0.body, $0.meetingTitle ?? "", $0.clientName ?? ""] }
        strings += shelfFolderNames
        strings.append(microphoneName)
        strings.append(meetingURL?.absoluteString ?? "")
        return strings.filter { !$0.isEmpty }
    }
}
