import Foundation

enum MemoryPressureLevel: Int, Comparable, Sendable {
    case normal
    case warning
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "Uyarı")
        case .critical: String(localized: "Kritik")
        }
    }

    var severity: PressureSeverity {
        switch self {
        case .normal: .none
        case .warning: .elevated
        case .critical: .critical
        }
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 4...: self = .critical
        case 2...3: self = .warning
        default: self = .normal
        }
    }
}

enum SystemThermalLevel: Int, Comparable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }

    var title: String {
        switch self {
        case .nominal: String(localized: "Serin")
        case .fair: String(localized: "Ilık")
        case .serious: String(localized: "Sıcak")
        case .critical: String(localized: "Kritik")
        }
    }

    var severity: PressureSeverity {
        switch self {
        case .nominal, .fair: .none
        case .serious: .elevated
        case .critical: .critical
        }
    }
}

/// Free space classification of the startup volume.
enum DiskSpacePolicy {
    static let bytesPerGigabyte: Int64 = 1_000_000_000
    static let defaultThresholdGigabytes = 10
    static let thresholdGigabyteOptions = [5, 10, 20, 50]
    /// Below this fraction of the threshold the warning becomes critical.
    static let criticalFraction: Double = 0.25

    static func severity(freeBytes: Int64, thresholdGigabytes: Int) -> PressureSeverity {
        let threshold = Int64(thresholdGigabytes) * bytesPerGigabyte
        guard threshold > 0, freeBytes < threshold else { return .none }
        let critical = Int64(Double(threshold) * criticalFraction)
        return freeBytes < critical ? .critical : .elevated
    }

    static func isLow(freeBytes: Int64, thresholdGigabytes: Int) -> Bool {
        severity(freeBytes: freeBytes, thresholdGigabytes: thresholdGigabytes) != .none
    }
}

enum PressureSeverity: Int, Comparable, Sendable {
    case none
    case elevated
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum PressureAlertDecision: Equatable, Sendable {
    case raise(PressureSeverity)
    case recovered
}

/// Coalesces a flapping severity signal into few alerts:
/// - escalation raises (unless the same severity was raised within `cooldown`),
/// - de-escalation to a lower non-zero severity stays quiet,
/// - returning to `.none` reports recovery once, and only if an alert was shown.
struct PressureAlertGate {
    let cooldown: TimeInterval
    private(set) var activeSeverity: PressureSeverity = .none
    private(set) var isAlertShowing = false
    private var lastRaised: [PressureSeverity: Date] = [:]

    init(cooldown: TimeInterval) {
        self.cooldown = cooldown
    }

    mutating func evaluate(_ severity: PressureSeverity, at date: Date) -> PressureAlertDecision? {
        guard severity != activeSeverity else { return nil }
        let previous = activeSeverity
        activeSeverity = severity

        if severity == .none {
            guard isAlertShowing else { return nil }
            isAlertShowing = false
            return .recovered
        }
        guard severity > previous else { return nil }
        if let last = lastRaised[severity], date.timeIntervalSince(last) < cooldown {
            return nil
        }
        lastRaised[severity] = date
        isAlertShowing = true
        return .raise(severity)
    }
}
