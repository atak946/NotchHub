import Foundation
import Testing
@testable import NotchHub

struct VPNDetectionTests {
    @Test(arguments: ["utun0", "utun12", "ipsec0", "ppp0", "tun1", "tap0", "UTUN3"])
    func tunnelInterfacesAreRecognized(_ name: String) {
        #expect(VPNInterfaceClassifier.isTunnel(name))
    }

    @Test(arguments: ["en0", "en7", "lo0", "bridge0", "awdl0", "llw0", "utunx", "anpi0", "gif0"])
    func otherInterfacesAreNotTunnels(_ name: String) {
        #expect(!VPNInterfaceClassifier.isTunnel(name))
    }

    @Test func unknownBeforeFirstPathUpdate() {
        let sample = VPNSample(isNetworkReachable: nil, primaryInterface: nil, tunnelInterfaces: [])
        #expect(VPNClassifier.state(for: sample) == .unknown)
    }

    @Test func splitTunnelWithIPv4IsConnected() {
        let sample = VPNSample(isNetworkReachable: true, primaryInterface: "en0", tunnelInterfaces: ["utun5"])
        #expect(VPNClassifier.state(for: sample) == .connected)
    }

    @Test func fullTunnelPrimaryInterfaceIsConnected() {
        let sample = VPNSample(isNetworkReachable: true, primaryInterface: "utun5", tunnelInterfaces: [])
        #expect(VPNClassifier.state(for: sample) == .connected)
    }

    @Test func onlineWithoutTunnelIsDisconnected() {
        let sample = VPNSample(isNetworkReachable: true, primaryInterface: "en0", tunnelInterfaces: [])
        #expect(VPNClassifier.state(for: sample) == .disconnected)
    }

    @Test func offlineWithoutTunnelIsUnknown() {
        let sample = VPNSample(isNetworkReachable: false, primaryInterface: nil, tunnelInterfaces: [])
        #expect(VPNClassifier.state(for: sample) == .unknown)
    }

    @Test func trackerReportsDropAndReconnect() {
        var tracker = VPNTransitionTracker()

        #expect(tracker.handle(.connected) == nil)
        #expect(tracker.handle(.disconnected) == .dropped)
        #expect(tracker.isDropped)
        #expect(tracker.handle(.connected) == .reconnected)
        #expect(!tracker.isDropped)
    }

    @Test func trackerIgnoresInitialDisconnectedAndFirstConnect() {
        var tracker = VPNTransitionTracker()

        #expect(tracker.handle(.disconnected) == nil)
        #expect(tracker.handle(.connected) == nil)
    }

    @Test func unknownInBetweenStillReportsDrop() {
        var tracker = VPNTransitionTracker()
        _ = tracker.handle(.connected)

        #expect(tracker.handle(.unknown) == nil)
        #expect(tracker.handle(.disconnected) == .dropped)
    }

    @Test func catalogCoversKnownClients() {
        let names = VPNClientCatalog.all.map(\.displayName)
        #expect(names.count == 9)
        #expect(Set(VPNClientCatalog.all.map(\.id)).count == names.count)
        #expect(VPNClientCatalog.all.allSatisfy { !$0.bundleIdentifiers.isEmpty && !$0.appPaths.isEmpty })
        #expect(VPNClientCatalog.all.allSatisfy { client in client.nameHints.allSatisfy { $0 == $0.lowercased() } })
    }

    @Test(arguments: [
        ("com.cisco.secureclient.gui", "cisco"),
        ("com.cisco.anyconnect.gui", "cisco"),
        ("com.paloaltonetworks.GlobalProtect.client", "globalprotect"),
        ("com.fortinet.FortiClient", "forticlient"),
        ("net.pulsesecure.Pulse-Secure", "ivanti"),
        ("org.openvpn.client.app", "openvpn"),
        ("net.tunnelblick.tunnelblick", "tunnelblick"),
        ("com.wireguard.macos", "wireguard"),
        ("io.tailscale.ipn.macos", "tailscale"),
    ])
    func runningClientMatchedByBundleIdentifier(_ bundleID: String, _ expected: String) {
        let apps = [SystemRunningApp(bundleIdentifier: bundleID, name: "Something")]
        #expect(VPNClientLocator.runningClient(in: apps)?.id == expected)
    }

    @Test(arguments: [("Pulse Secure", "ivanti"), ("NordLayer", "nordlayer"), ("Cisco AnyConnect", "cisco")])
    func runningClientMatchedByName(_ name: String, _ expected: String) {
        let apps = [SystemRunningApp(bundleIdentifier: "x.y", name: name)]
        #expect(VPNClientLocator.runningClient(in: apps)?.id == expected)
    }

    @Test func runningClientMatchedByInstalledBundleIdentifier() throws {
        let nordLayer = try #require(VPNClientCatalog.client(id: "nordlayer"))
        let installed = [VPNInstalledClient(
            client: nordLayer,
            appURL: URL(fileURLWithPath: "/Applications/NordLayer.app"),
            bundleIdentifier: "com.example.renamed-nordlayer"
        )]
        let apps = [SystemRunningApp(bundleIdentifier: "com.example.renamed-nordlayer", name: "Agent")]
        #expect(VPNClientLocator.runningClient(in: apps, installed: installed)?.id == "nordlayer")
    }

    @Test func unrelatedAppsAreNotClients() {
        let apps = [SystemRunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                    SystemRunningApp(bundleIdentifier: nil, name: nil)]
        #expect(VPNClientLocator.runningClient(in: apps) == nil)
    }

    @MainActor
    @Test func installedClientsKeepCatalogOrderAndFallBackToKnownIdentifier() {
        let installedIDs: Set<String> = ["tailscale", "forticlient"]
        let found = VPNClientLocator.installedClients { client in
            installedIDs.contains(client.id) ? URL(fileURLWithPath: "/nonexistent/\(client.id).app") : nil
        }
        #expect(found.map(\.client.id) == ["forticlient", "tailscale"])
        #expect(found.first?.bundleIdentifier == "com.fortinet.FortiClient")
    }

    @Test func bundleIdentifierReadFromInfoPlist() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appending(path: "SystemVPNTest-\(UUID().uuidString).app")
        let contents = appURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appURL) }
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.vpn"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))

        #expect(VPNClientLocator.bundleIdentifier(appURL: appURL) == "com.example.vpn")
        #expect(VPNClientLocator.bundleIdentifier(appURL: appURL.appending(path: "missing")) == nil)
    }
}
