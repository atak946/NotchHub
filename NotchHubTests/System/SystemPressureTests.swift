import Foundation
import Testing
@testable import NotchHub

struct SystemPressurePolicyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let gigabyte = DiskSpacePolicy.bytesPerGigabyte

    @Test func diskThreshold() {
        #expect(DiskSpacePolicy.isLow(freeBytes: 9 * gigabyte, thresholdGigabytes: 10))
        #expect(!DiskSpacePolicy.isLow(freeBytes: 10 * gigabyte, thresholdGigabytes: 10))
        #expect(!DiskSpacePolicy.isLow(freeBytes: 200 * gigabyte, thresholdGigabytes: 10))
        #expect(DiskSpacePolicy.severity(freeBytes: 9 * gigabyte, thresholdGigabytes: 10) == .elevated)
        #expect(DiskSpacePolicy.severity(freeBytes: 2 * gigabyte, thresholdGigabytes: 10) == .critical)
        #expect(DiskSpacePolicy.severity(freeBytes: 0, thresholdGigabytes: 0) == .none)
    }

    @Test func levelMappings() {
        #expect(MemoryPressureLevel(kernelLevel: 1) == .normal)
        #expect(MemoryPressureLevel(kernelLevel: 2) == .warning)
        #expect(MemoryPressureLevel(kernelLevel: 4) == .critical)
        #expect(SystemThermalLevel(.fair).severity == .none)
        #expect(SystemThermalLevel(.serious).severity == .elevated)
        #expect(SystemThermalLevel(.critical).severity == .critical)
    }

    @Test func gateRaisesEscalatesAndRecovers() {
        var gate = PressureAlertGate(cooldown: 60)

        #expect(gate.evaluate(.none, at: start) == nil)
        #expect(gate.evaluate(.elevated, at: start) == .raise(.elevated))
        #expect(gate.evaluate(.elevated, at: start) == nil)
        #expect(gate.evaluate(.critical, at: start) == .raise(.critical))
        #expect(gate.evaluate(.elevated, at: start) == nil)
        #expect(gate.evaluate(.none, at: start) == .recovered)
    }

    @Test func gateSuppressesFlapsWithinCooldown() {
        var gate = PressureAlertGate(cooldown: 60)
        _ = gate.evaluate(.elevated, at: start)
        _ = gate.evaluate(.none, at: start.addingTimeInterval(1))

        #expect(gate.evaluate(.elevated, at: start.addingTimeInterval(30)) == nil)
        #expect(gate.evaluate(.none, at: start.addingTimeInterval(31)) == nil)
        #expect(gate.evaluate(.elevated, at: start.addingTimeInterval(61)) == .raise(.elevated))
    }
}

@MainActor
struct SystemPressureMonitorTests {
    private let clock = SystemTestClock()
    private let reader = SystemTestPressureReader()
    private let alerts = SystemTestSupport.makeAlertCenter()

    private func makeMonitor() -> SystemPressureMonitor {
        let monitor = SystemPressureMonitor(
            alerts: alerts, reader: reader, clock: clock, defaults: SystemTestSupport.makeDefaults()
        )
        monitor.start()
        return monitor
    }

    @Test func calmSystemPostsNothing() {
        let monitor = makeMonitor()

        #expect(alerts.current == nil)
        #expect(monitor.worstSeverity == .none)
        #expect(monitor.freeDiskBytes == reader.freeBytes)
    }

    @Test func memoryAlertsCoalesceUnderOneKey() {
        let monitor = makeMonitor()

        monitor.handleMemory(.warning)
        #expect(alerts.current?.title == "Bellek baskısı yüksek")
        #expect(alerts.current?.style == .reminder)

        monitor.handleMemory(.critical)
        #expect(alerts.current?.title == "Bellek baskısı kritik")
        #expect(alerts.current?.style == .urgent)
        #expect(alerts.queue.isEmpty)

        monitor.handleMemory(.normal)
        #expect(alerts.current?.title == "Bellek baskısı normale döndü")
        #expect(alerts.current?.style == .success)
        #expect(alerts.queue.isEmpty)
    }

    @Test func repeatedWarningWithinCooldownIsSuppressed() {
        let monitor = makeMonitor()
        monitor.handleMemory(.warning)
        monitor.handleMemory(.normal)
        alerts.dismissAll()

        clock.advance(by: 60)
        monitor.handleMemory(.warning)

        #expect(alerts.current == nil)
        #expect(monitor.memoryPressure == .warning)
    }

    @Test func differentSignalsQueueSeparately() {
        let monitor = makeMonitor()

        monitor.handleMemory(.warning)
        monitor.handleThermal(.serious)

        #expect(alerts.current?.coalescingKey == SystemPressureMonitor.AlertKey.memory)
        #expect(alerts.queue.map(\.coalescingKey) == [SystemPressureMonitor.AlertKey.thermal])
    }

    @Test func lowDiskAlertsOnceAcrossChecks() {
        let monitor = makeMonitor()
        reader.freeBytes = 8 * DiskSpacePolicy.bytesPerGigabyte

        monitor.checkDisk()
        #expect(alerts.current?.title == "Disk alanı az")
        #expect(monitor.isDiskLow)
        alerts.dismissAll()

        clock.advance(by: SystemPressureMonitor.diskCheckInterval)
        monitor.checkDisk()
        #expect(alerts.current == nil)
    }

    @Test func alertsCanBeSwitchedOff() {
        let monitor = makeMonitor()
        monitor.alertsEnabled = false

        monitor.handleThermal(.critical)

        #expect(alerts.current == nil)
        #expect(monitor.thermalLevel == .critical)
        #expect(monitor.worstSeverity == .critical)
    }
}
