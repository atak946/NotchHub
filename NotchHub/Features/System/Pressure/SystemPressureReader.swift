import Darwin
import Foundation
import OSLog

/// Memory pressure, thermal state and free disk space. Side-effect boundary of `SystemPressureMonitor`.
@MainActor
protocol SystemPressureReading: AnyObject {
    func currentMemoryPressure() -> MemoryPressureLevel
    func currentThermalLevel() -> SystemThermalLevel
    /// Free bytes on the startup volume ("important usage" capacity, like Finder).
    func freeDiskBytes() -> Int64?
    func startObserving(
        memory: @escaping @MainActor (MemoryPressureLevel) -> Void,
        thermal: @escaping @MainActor (SystemThermalLevel) -> Void
    )
    func stopObserving()
}

@MainActor
final class SystemPressureReader: SystemPressureReading {
    private static let pressureSysctl = "kern.memorystatus_vm_pressure_level"
    private static let startupVolume = URL(fileURLWithPath: "/")

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "SystemPressure")
    private var memorySource: (any DispatchSourceMemoryPressure)?
    private var thermalObserver: NSObjectProtocol?

    func currentMemoryPressure() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(Self.pressureSysctl, &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressureLevel(kernelLevel: level)
    }

    func currentThermalLevel() -> SystemThermalLevel {
        SystemThermalLevel(ProcessInfo.processInfo.thermalState)
    }

    func freeDiskBytes() -> Int64? {
        do {
            let values = try Self.startupVolume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            logger.error("Reading free disk space failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func startObserving(
        memory: @escaping @MainActor (MemoryPressureLevel) -> Void,
        thermal: @escaping @MainActor (SystemThermalLevel) -> Void
    ) {
        guard memorySource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            let level: MemoryPressureLevel = event.contains(.critical) ? .critical
                : event.contains(.warning) ? .warning : .normal
            MainActor.assumeIsolated { memory(level) }
        }
        source.activate()
        memorySource = source

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let level = SystemThermalLevel(ProcessInfo.processInfo.thermalState)
            MainActor.assumeIsolated { thermal(level) }
        }
    }

    func stopObserving() {
        memorySource?.cancel()
        memorySource = nil
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        thermalObserver = nil
    }
}
