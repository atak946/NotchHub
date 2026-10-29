import Foundation
import Testing
@testable import NotchHub

@MainActor
struct ProfilesServiceTests {
    private let defaults = makeProfilesTestDefaults()
    private let alerts = makeProfilesTestAlerts()
    private let executor = ProfilesFakeExecutor()

    private func makeService() -> ProfilesService {
        ProfilesService(
            store: ProfilesStore(defaults: defaults),
            alerts: alerts,
            executor: executor,
            validator: makeProfilesPermissiveValidator(),
            scanner: ProfilesWorkspaceScanner(fileSystem: ProfilesFakeFileSystem())
        )
    }

    private func makeProfile() -> ClientProfile {
        ClientProfile(
            name: "Acme",
            steps: [ProfileStep(action: .dockerComposeUp(path: "/w/acme")), ProfileStep(action: .openInVSCode(path: "/w/acme"))],
            deactivateSteps: [ProfileStep(action: .dockerComposeStop(path: "/w/acme"))]
        )
    }

    @Test func successfulRunActivatesProfileAndPostsSuccess() async {
        let service = makeService()
        let profile = makeProfile()
        service.store.save(profile)

        await service.activate(profile.id)?.value

        #expect(service.store.activeProfileID == profile.id)
        #expect(!service.isRunning)
        #expect(alerts.current?.style == .success)
        #expect(alerts.current?.coalescingKey == ProfilesService.alertKey(for: profile.id))
        #expect(service.lastReports[profile.id]?.outcome == .succeeded)
    }

    @Test func failedRunPostsUrgentRetryAlert() async {
        let service = makeService()
        let profile = makeProfile()
        service.store.save(profile)
        executor.behavior = { _ in .fail("docker missing") }

        await service.activate(profile.id)?.value

        #expect(service.store.activeProfileID == nil)
        #expect(alerts.current?.style == .urgent)
        #expect(alerts.current?.actionTitle == "Yeniden dene")
        #expect(alerts.current?.subtitle?.contains("docker missing") == true)
    }

    @Test func secondRunIsIgnoredWhileRunning() async {
        let service = makeService()
        let profile = makeProfile()
        service.store.save(profile)
        executor.behavior = { _ in .hang }

        let first = service.activate(profile.id)
        await profilesWaitUntil { executor.hangStarted }
        #expect(service.runState?.profileID == profile.id)
        #expect(service.activate(profile.id) == nil)

        service.cancel()
        await first?.value
        #expect(!service.isRunning)
        #expect(service.lastReports[profile.id]?.outcome == .cancelled)
    }

    @Test func deactivateRunsTeardownAndClearsActive() async {
        let service = makeService()
        let profile = makeProfile()
        service.store.save(profile)
        await service.activate(profile.id)?.value

        await service.deactivate(profile.id)?.value

        #expect(executor.executed.last == .dockerComposeStop(path: "/w/acme"))
        #expect(service.store.activeProfileID == nil)
    }

    @Test func alertsCanBeDisabled() async {
        let service = makeService()
        service.store.alertsEnabled = false
        let profile = makeProfile()
        service.store.save(profile)

        await service.activate(profile.id)?.value

        #expect(alerts.current == nil)
    }

    @Test func createProfileFromSuggestionPersists() {
        let service = makeService()
        let suggestion = ProfilesWorkspaceSuggestion(path: "/w/acme", kinds: [.compose, .dotnet])

        let profile = service.createProfile(from: suggestion)

        #expect(service.store.profiles == [profile])
        #expect(profile.name == "acme")
        #expect(profile.steps.map(\.action.kind) == [.dockerComposeUp, .openInVSCode, .openTerminal])
        #expect(profile.deactivateSteps.map(\.action) == [.dockerComposeStop(path: "/w/acme")])
    }
}
