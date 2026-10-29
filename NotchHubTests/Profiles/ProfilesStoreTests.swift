import Foundation
import Testing
@testable import NotchHub

@MainActor
struct ProfilesStoreTests {
    private let defaults = makeProfilesTestDefaults()

    @Test func defaultsAreSensible() {
        let store = ProfilesStore(defaults: defaults)
        #expect(store.profiles.isEmpty)
        #expect(store.activeProfileID == nil)
        #expect(store.alertsEnabled)
        #expect(store.remoteMonitorEnabled)
        #expect(store.vpnAppBundleID == nil)
        #expect(store.terminalBundleID == "com.apple.Terminal")
    }

    @Test func vpnClientDefaultsToFirstInstalled() throws {
        let wireGuard = try #require(VPNClientCatalog.client(id: "wireguard"))
        let tailscale = try #require(VPNClientCatalog.client(id: "tailscale"))
        let installed = [wireGuard, tailscale].map {
            VPNInstalledClient(client: $0, appURL: URL(fileURLWithPath: $0.appPaths[0]), bundleIdentifier: $0.bundleIdentifiers[0])
        }
        let store = ProfilesStore(defaults: defaults, installedVPNClients: { installed })

        #expect(store.effectiveVPNAppBundleID == "com.wireguard.macos")
        #expect(store.executorConfiguration.vpnAppBundleID == "com.wireguard.macos")
        store.vpnAppBundleID = "io.tailscale.ipn.macsys"
        #expect(store.executorConfiguration.vpnAppBundleID == "io.tailscale.ipn.macsys")
    }

    @Test func vpnClientWithoutInstalledClientsIsNil() {
        let store = ProfilesStore(defaults: defaults, installedVPNClients: { [] })
        #expect(store.effectiveVPNAppBundleID == nil)
    }

    @Test func previouslyStoredVPNBundleIDIsKept() {
        defaults.set("com.example.custom-vpn", forKey: ProfilesStore.Keys.vpnAppBundleID)
        let store = ProfilesStore(defaults: defaults, installedVPNClients: { [] })
        #expect(store.vpnAppBundleID == "com.example.custom-vpn")
        #expect(store.effectiveVPNAppBundleID == "com.example.custom-vpn")
    }

    @Test func emptyStoredVPNBundleIDMeansAutomatic() {
        defaults.set("", forKey: ProfilesStore.Keys.vpnAppBundleID)
        #expect(ProfilesStore(defaults: defaults, installedVPNClients: { [] }).vpnAppBundleID == nil)
    }

    @Test func profilesRoundTripThroughDefaults() {
        let profile = ClientProfile(
            name: "Acme",
            color: .orange,
            steps: [
                ProfileStep(action: .waitForVPN(timeoutSeconds: 60)),
                ProfileStep(action: .openURL("rdm://open"), continueOnFailure: true),
                ProfileStep(action: .dockerComposeUp(path: "/w/acme")),
            ],
            deactivateSteps: [ProfileStep(action: .dockerComposeStop(path: "/w/acme"))]
        )
        let store = ProfilesStore(defaults: defaults)
        store.save(profile)
        store.activeProfileID = profile.id
        store.remoteAlertsEnabled = false

        let reloaded = ProfilesStore(defaults: defaults)
        #expect(reloaded.profiles == [profile])
        #expect(reloaded.activeProfileID == profile.id)
        #expect(!reloaded.remoteAlertsEnabled)
    }

    @Test func saveReplacesByIDAndDeleteClearsActive() {
        let store = ProfilesStore(defaults: defaults)
        var profile = ClientProfile(name: "Acme")
        store.save(profile)
        profile.name = "Acme Corp"
        store.save(profile)
        #expect(store.profiles.map(\.name) == ["Acme Corp"])

        store.activeProfileID = profile.id
        store.delete(id: profile.id)
        #expect(store.profiles.isEmpty)
        #expect(store.activeProfileID == nil)
    }

    @Test func staleActiveIDIsDropped() {
        defaults.set(UUID().uuidString, forKey: ProfilesStore.Keys.activeProfileID)
        #expect(ProfilesStore(defaults: defaults).activeProfileID == nil)
    }

    @Test func corruptDataYieldsEmptyList() {
        defaults.set(Data("nope".utf8), forKey: ProfilesStore.Keys.profiles)
        #expect(ProfilesStore(defaults: defaults).profiles.isEmpty)
    }

    @Test func moveAndQuickLaunchLimit() {
        let store = ProfilesStore(defaults: defaults)
        let names = (1...8).map { "P\($0)" }
        names.forEach { store.save(ClientProfile(name: $0)) }
        store.move(fromOffsets: IndexSet(integer: 7), toOffset: 0)

        #expect(store.profiles.first?.name == "P8")
        #expect(store.quickLaunchProfiles.count == ProfilesStore.maxQuickLaunchProfiles)
        #expect(ProfilesStore(defaults: defaults).profiles.first?.name == "P8")
    }

    @Test func usedFolderPathsCoverBothStepLists() {
        let store = ProfilesStore(defaults: defaults)
        store.save(ClientProfile(
            name: "A",
            steps: [ProfileStep(action: .openInVSCode(path: "/w/a")), ProfileStep(action: .openApp(bundleID: "x.y"))],
            deactivateSteps: [ProfileStep(action: .dockerComposeStop(path: "/w/b"))]
        ))
        #expect(store.usedFolderPaths == ["/w/a", "/w/b"])
    }
}
