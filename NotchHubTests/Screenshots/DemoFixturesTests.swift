import AppKit
import Testing
@testable import NotchHub

/// README screenshots must only ever show static demo content, never anything from this machine.
@MainActor
struct DemoFixturesTests {
    /// Values that identify the machine or its user; none may appear in the demo data.
    private var environmentStrings: [String] {
        let info = ProcessInfo.processInfo
        let candidates = [
            NSUserName(),
            NSFullUserName(),
            info.hostName,
            Host.current().localizedName ?? "",
            NSHomeDirectory(),
            FileManager.default.homeDirectoryForCurrentUser.lastPathComponent,
            TimeZone.current.identifier,
        ]
        return candidates.filter { $0.count >= 3 }
    }

    @Test func demoStringsContainNothingFromTheUserEnvironment() {
        for value in DemoFixtures.allStrings {
            for secret in environmentStrings {
                #expect(!value.localizedCaseInsensitiveContains(secret), "\(value) contains \(secret)")
            }
            #expect(!value.contains("/Users/"))
            #expect(!value.contains("@"), "No e-mail addresses in demo data")
        }
    }

    @Test func demoDataIsStatic() {
        #expect(DemoFixtures.allStrings == DemoFixtures.allStrings)
        #expect(DemoFixtures.events == DemoFixtures.events)
        #expect(DemoFixtures.notes == DemoFixtures.notes)
        #expect(DemoFixtures.track.title == "Midnight Drive")
        #expect(DemoFixtures.messageSender == "Ayşe Demir")
        #expect(!DemoFixtures.allStrings.isEmpty)
    }

    @Test func meetingLinksUseTheReservedExampleDomain() {
        #expect(DemoFixtures.meetingURL?.host() == "example.com")
    }

    @Test func calendarEventsDependOnlyOnTheGivenTime() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let source = DemoCalendarSource(now: now)
        let events = try source.events(from: now, to: now.addingTimeInterval(24 * 3600))
        let again = try DemoCalendarSource(now: now).events(from: now, to: now.addingTimeInterval(24 * 3600))
        #expect(events == again)
        #expect(events.map(\.title) == DemoFixtures.events.map(\.title))
        #expect(events.first?.start == now.addingTimeInterval(12 * 60))
        #expect(source.authorization == .authorized)
    }

    @Test func notesComeFromTheFixturesAndAreNeverSaved() throws {
        let storage = DemoNotesStorage(now: Date(timeIntervalSinceReferenceDate: 0))
        let notes = try storage.load()
        #expect(notes.map(\.body) == DemoFixtures.notes.map(\.body))
        try storage.save([])
        #expect(try storage.load().count == DemoFixtures.notes.count)
    }

    @Test func mediaProviderReportsTheFixtureTrack() async throws {
        let provider = DemoMediaProvider(artwork: DemoArtwork.pngData())
        let track = try await provider.fetchNowPlaying()
        #expect(track?.title == DemoFixtures.track.title)
        #expect(track?.artist == DemoFixtures.track.artist)
        #expect(try await provider.fetchArtwork(for: try #require(track)) != nil)
    }

    @Test func demoServicesNeverBuildTheLiveOnes() throws {
        let environment = try DemoEnvironment()
        defer { environment.cleanUp() }
        let before = ModuleCoreServices.liveCreationCount
        let settings = SettingsStore(defaults: environment.defaults)
        let services = ModuleServices(
            settings: settings,
            alerts: NotchAlertCenter(),
            core: .demo(in: environment, now: Date())
        )
        #expect(ModuleCoreServices.liveCreationCount == before)
        #expect(services.weather.displaySnapshot(at: Date())?.temperature == DemoFixtures.weather.temperature)
    }

    @Test func weatherSnapshotUsesNoRealPlace() {
        let snapshot = DemoWeather.snapshot(at: Date(timeIntervalSinceReferenceDate: 0))
        #expect(snapshot.placeName == nil)
        #expect(snapshot.coordinate == WeatherCoordinate(latitude: 0, longitude: 0))
    }
}

struct ScreenshotModeTests {
    @Test func readsTheOutputFolderFromTheArgument() {
        let url = ScreenshotMode.outputDirectory(arguments: ["app", "--render-screenshots", "/tmp/shots"], environment: [:])
        #expect(url?.path == "/tmp/shots")
    }

    @Test func fallsBackToTheEnvironment() {
        let url = ScreenshotMode.outputDirectory(arguments: ["app"], environment: [ScreenshotMode.environmentKey: "/tmp/env"])
        #expect(url?.path == "/tmp/env")
    }

    @Test func isOffWithoutARequestOrAFolder() {
        #expect(ScreenshotMode.outputDirectory(arguments: ["app"], environment: [:]) == nil)
        #expect(ScreenshotMode.outputDirectory(arguments: ["app", "--render-screenshots"], environment: [:]) == nil)
        #expect(ScreenshotMode.outputDirectory(arguments: ["app", "--render-screenshots", "-AppleLanguages"], environment: [:]) == nil)
    }
}

struct DemoClockTests {
    @Test(arguments: 0..<24)
    func everyUTCHourMapsToMidMorning(hour: Int) throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let date = try #require(utc.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: hour, minute: 30)))
        let offset = DemoClock.offsetHours(at: date)
        #expect((-12...11).contains(offset))
        var local = Calendar(identifier: .gregorian)
        local.timeZone = DemoClock.timeZone(at: date)
        #expect(local.component(.hour, from: date) == DemoClock.targetHour)
    }

    @Test func posixNamesInvertTheSign() {
        #expect(DemoClock.posixIdentifier(offsetHours: 3) == "Etc/GMT-3")
        #expect(DemoClock.posixIdentifier(offsetHours: -5) == "Etc/GMT+5")
        #expect(DemoClock.posixIdentifier(offsetHours: 0) == "Etc/GMT")
    }
}

struct PNGQuantizerTests {
    @Test func producesAPalettePNGNoLargerThanTheSource() throws {
        let data = try #require(DemoArtwork.pngData())
        let source = try #require(NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let quantized = try #require(PNGQuantizer.pngData(from: source))
        let decoded = try #require(NSImage(data: quantized))
        #expect(decoded.size.width == CGFloat(DemoArtwork.size))
        #expect(quantized.count < data.count)
    }
}
