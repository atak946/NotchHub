import AppKit
import Foundation
import OSLog

/// The app's real view models wired to demo services, ready to be put into each screenshot state.
@MainActor
final class DemoStage {
    /// A 14" MacBook Pro screen with its notch.
    static let geometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchSize: CGSize(width: 185, height: 32),
        hasPhysicalNotch: true
    )
    private static let artworkTimeout: Duration = .seconds(3)
    private static let pollStep: Duration = .milliseconds(20)

    let environment: DemoEnvironment
    let settings: SettingsStore
    let alerts: NotchAlertCenter
    let services: ModuleServices
    let model: NotchViewModel
    let language: AppLanguageSettings
    let updater: UpdaterService
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Screenshots")

    init(now: Date) throws {
        let environment = try DemoEnvironment()
        self.environment = environment
        settings = SettingsStore(defaults: environment.defaults)
        alerts = NotchAlertCenter()
        services = ModuleServices(
            settings: settings,
            alerts: alerts,
            core: .demo(in: environment, now: now)
        )
        model = NotchViewModel(geometry: Self.geometry, settings: settings, services: services)
        language = AppLanguageSettings(store: AppLanguageStore(defaults: environment.defaults, domainName: "demo"))
        updater = UpdaterService(alerts: alerts, configuration: UpdaterConfiguration(infoDictionary: [:]))
    }

    /// Loads the fixtures into the services. Nothing is started, so no live source is ever polled.
    func prepare() async {
        _ = await services.media.refresh()
        await waitForArtwork()
        services.calendar.refresh()
        services.notes.start()
        services.notes.selectedID = services.notes.sortedNotes.first?.id
        fillShelf()
        services.system.micCamera.apply(CaptureSnapshot(activeMicrophones: [DemoFixtures.microphoneName], activeCameras: []))
    }

    func startTimer() {
        services.timer.start(duration: DemoFixtures.timerMinutes)
    }

    func reset() {
        alerts.dismissAll()
        services.hud.center.hide()
        model.isExpanded = false
    }

    private func waitForArtwork() async {
        let deadline = ContinuousClock.now.advanced(by: Self.artworkTimeout)
        while services.media.artwork == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.pollStep)
        }
    }

    private func fillShelf() {
        let shelf = services.shelf
        let folder = environment.subdirectory("Files")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let urls = DemoFixtures.shelfFolderNames.map { folder.appendingPathComponent($0, isDirectory: true) }
            for url in urls {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            shelf.add(fileURLs: urls)
        } catch {
            logger.error("Demo shelf folders could not be created: \(error.localizedDescription, privacy: .public)")
        }
        if let image = DemoArtwork.pngData(DemoArtwork.photo) {
            shelf.add(imageData: image)
        }
        shelf.add(text: DemoFixtures.shelfText)
    }
}
