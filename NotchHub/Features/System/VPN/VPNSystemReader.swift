import Darwin
import Foundation
import Network
import OSLog
import SystemConfiguration

/// Reads VPN-related network state and reports changes. Side-effect boundary of `VPNMonitor`.
@MainActor
protocol VPNSystemReading: AnyObject {
    func sample() -> VPNSample
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// NWPathMonitor + SCDynamicStore + getifaddrs.
@MainActor
final class SystemVPNReader: VPNSystemReading {
    private static let globalIPv4Key = "State:/Network/Global/IPv4"
    private static let interfaceIPv4Pattern = "State:/Network/Interface/.*/IPv4"
    private static let primaryInterfaceKey = "PrimaryInterface"
    private static let storeName = "\(AppIdentity.bundleID).VPN" as CFString

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "VPN")
    private var pathMonitor: NWPathMonitor?
    private var isReachable: Bool?
    private var store: SCDynamicStore?
    private var storeCallback: SystemDynamicStoreCallback?
    private var onChange: (@MainActor () -> Void)?

    func sample() -> VPNSample {
        VPNSample(
            isNetworkReachable: isReachable,
            primaryInterface: primaryInterface(),
            tunnelInterfaces: Self.tunnelInterfacesWithIPv4()
        )
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        startPathMonitor()
        startDynamicStore()
    }

    func stopObserving() {
        pathMonitor?.cancel()
        pathMonitor = nil
        isReachable = nil
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        store = nil
        storeCallback = nil
        onChange = nil
    }

    // MARK: - NWPathMonitor

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            MainActor.assumeIsolated {
                self?.isReachable = reachable
                self?.onChange?()
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    // MARK: - SCDynamicStore

    private func startDynamicStore() {
        let callback = SystemDynamicStoreCallback { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let handler: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<SystemDynamicStoreCallback>.fromOpaque(info).takeUnretainedValue().handler()
        }
        guard let store = SCDynamicStoreCreate(nil, Self.storeName, handler, &context) else {
            logger.error("SCDynamicStoreCreate failed")
            return
        }
        let keys = [Self.globalIPv4Key] as CFArray
        let patterns = [Self.interfaceIPv4Pattern] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns),
              SCDynamicStoreSetDispatchQueue(store, .main)
        else {
            logger.error("Observing SCDynamicStore failed")
            return
        }
        self.store = store
        storeCallback = callback
    }

    private func primaryInterface() -> String? {
        let store = store ?? SCDynamicStoreCreate(nil, Self.storeName, nil, nil)
        guard let store,
              let value = SCDynamicStoreCopyValue(store, Self.globalIPv4Key as CFString) as? [String: Any]
        else { return nil }
        return value[Self.primaryInterfaceKey] as? String
    }

    // MARK: - getifaddrs

    nonisolated static func tunnelInterfacesWithIPv4() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        let requiredFlags = UInt32(IFF_UP | IFF_RUNNING)
        var names: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET),
                  entry.ifa_flags & requiredFlags == requiredFlags
            else { continue }
            let name = String(cString: entry.ifa_name)
            if VPNInterfaceClassifier.isTunnel(name), !names.contains(name) {
                names.append(name)
            }
        }
        return names.sorted()
    }
}

/// Box handed to SCDynamicStore as callback info (the C callback cannot capture context).
final class SystemDynamicStoreCallback: Sendable {
    let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}
