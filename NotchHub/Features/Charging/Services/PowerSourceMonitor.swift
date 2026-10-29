import CoreFoundation
import Foundation
import IOKit.ps
import OSLog

/// Internal battery readings plus a change signal, injectable for tests.
@MainActor
protocol PowerSourceMonitoring: AnyObject {
    /// `nil` on machines without a battery (desktops) or when IOKit cannot be read.
    func snapshot() -> PowerSnapshot?
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// Reads `IOPSCopyPowerSourcesInfo` and listens with `IOPSNotificationCreateRunLoopSource` on the main run loop.
@MainActor
final class IOKitPowerSourceMonitor: PowerSourceMonitoring {
    private var source: CFRunLoopSource?
    /// Retains `self` while the run loop source holds a raw pointer to it; released in `stopObserving`.
    private var retainedSelf: Unmanaged<IOKitPowerSourceMonitor>?
    private var onChange: (@MainActor () -> Void)?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Charging")

    func snapshot() -> PowerSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for powerSource in list {
            let description = IOPSGetPowerSourceDescription(info, powerSource)?.takeUnretainedValue()
            guard let values = description as? [String: Any] else { continue }
            if let snapshot = PowerSnapshotParser.snapshot(from: values) { return snapshot }
        }
        return nil
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard source == nil else { return }
        let retained = Unmanaged.passRetained(self)
        let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<IOKitPowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            // The source is added to the main run loop, so the callback always arrives on the main thread.
            MainActor.assumeIsolated { monitor.notifyChange() }
        }, retained.toOpaque())?.takeRetainedValue()
        guard let created else {
            retained.release()
            logger.error("IOPSNotificationCreateRunLoopSource failed; charging presentations are off")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        source = created
        retainedSelf = retained
    }

    func stopObserving() {
        onChange = nil
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        retainedSelf?.release()
        retainedSelf = nil
    }

    private func notifyChange() {
        onChange?()
    }
}
