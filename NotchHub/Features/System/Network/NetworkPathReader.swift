import CoreLocation
import CoreWLAN
import Foundation
import Network

/// Delivers network snapshots. Side-effect boundary of `NetworkMonitor`.
@MainActor
protocol NetworkPathReading: AnyObject {
    func startObserving(_ onUpdate: @escaping @MainActor (NetworkSnapshot) -> Void)
    func stopObserving()
}

/// NWPathMonitor-backed reader. The SSID is read via CoreWLAN only when Location access was already
/// granted; this reader never requests permission.
@MainActor
final class SystemNetworkPathReader: NetworkPathReading {
    private var monitor: NWPathMonitor?
    private let locationManager = CLLocationManager()

    func startObserving(_ onUpdate: @escaping @MainActor (NetworkSnapshot) -> Void) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            let kinds = path.availableInterfaces.map { Self.kind(of: $0.type) }
            let isExpensive = path.isExpensive
            let isConstrained = path.isConstrained
            MainActor.assumeIsolated {
                guard let self else { return }
                let kind = NetworkClassifier.primaryKind(of: kinds, isSatisfied: isSatisfied)
                onUpdate(NetworkSnapshot(
                    isOnline: isSatisfied,
                    interface: kind,
                    isExpensive: isExpensive,
                    isConstrained: isConstrained,
                    ssid: kind == .wifi ? self.currentSSID() : nil
                ))
            }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    func stopObserving() {
        monitor?.cancel()
        monitor = nil
    }

    private func currentSSID() -> String? {
        guard Self.canReadSSID(locationManager.authorizationStatus) else { return nil }
        return CWWiFiClient.shared().interface()?.ssid()
    }

    nonisolated static func canReadSSID(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways
    }

    nonisolated static func kind(of type: NWInterface.InterfaceType) -> NetworkInterfaceKind {
        switch type {
        case .wifi: .wifi
        case .wiredEthernet: .ethernet
        case .cellular: .cellular
        case .loopback: .loopback
        case .other: .other
        @unknown default: .other
        }
    }
}
