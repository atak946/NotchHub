import Foundation

enum EndpointHealthState: Equatable, Sendable {
    case unknown
    case up
    /// Reachable but slow, or one unconfirmed failure after being up.
    case degraded
    case down
    case pausedVPNOff

    var title: String {
        switch self {
        case .unknown: "Denetleniyor…"
        case .up: "Ayakta"
        case .degraded: "Yavaş"
        case .down: "Kapalı"
        case .pausedVPNOff: "Duraklatıldı (VPN kapalı)"
        }
    }
}

/// Raw result of one probe.
struct EndpointProbeResult: Equatable, Sendable {
    var statusCode: Int?
    var latency: TimeInterval
    var errorDescription: String?
    var certificateExpiry: Date?

    init(statusCode: Int? = nil, latency: TimeInterval = 0, errorDescription: String? = nil, certificateExpiry: Date? = nil) {
        self.statusCode = statusCode
        self.latency = latency
        self.errorDescription = errorDescription
        self.certificateExpiry = certificateExpiry
    }
}

enum EndpointCheckOutcome: Equatable, Sendable {
    case success(latency: TimeInterval)
    case failure(reason: String)
    case vpnUnavailable

    /// Maps a probe to an outcome: transport errors and unexpected status codes count as failures.
    static func classify(_ result: EndpointProbeResult, expected: ClosedRange<Int>) -> EndpointCheckOutcome {
        if let error = result.errorDescription {
            return .failure(reason: error)
        }
        guard let code = result.statusCode else {
            return .failure(reason: "Yanıt yok")
        }
        guard expected.contains(code) else {
            return .failure(reason: "HTTP \(code)")
        }
        return .success(latency: result.latency)
    }
}

enum EndpointTransition: Equatable, Sendable {
    case wentDown(reason: String)
    case recovered
}

/// Per-endpoint state machine with 2-failure confirmation before `down`.
struct EndpointHealthMachine: Equatable, Sendable {
    static let failuresToConfirmDown = 2
    /// Responses slower than this mark the endpoint degraded.
    static let slowLatencyThreshold: TimeInterval = 2

    private(set) var state: EndpointHealthState = .unknown
    private(set) var consecutiveFailures = 0

    init() {}

    mutating func record(_ outcome: EndpointCheckOutcome) -> EndpointTransition? {
        switch outcome {
        case .vpnUnavailable:
            state = .pausedVPNOff
            consecutiveFailures = 0
            return nil
        case .success(let latency):
            let wasDown = state == .down
            consecutiveFailures = 0
            state = latency > Self.slowLatencyThreshold ? .degraded : .up
            return wasDown ? .recovered : nil
        case .failure(let reason):
            consecutiveFailures += 1
            if consecutiveFailures >= Self.failuresToConfirmDown {
                let wasDown = state == .down
                state = .down
                return wasDown ? nil : .wentDown(reason: reason)
            }
            if state == .up {
                state = .degraded
            } else if state == .pausedVPNOff {
                state = .unknown
            }
            return nil
        }
    }
}

/// Decides when to warn about an expiring TLS certificate: within `warningLeadTime`, at most once per calendar day.
struct CertificateExpiryWarningPolicy: Equatable, Sendable {
    static let warningLeadTime: TimeInterval = 14 * 24 * 60 * 60

    private(set) var lastWarnings: [UUID: Date]

    init(lastWarnings: [UUID: Date] = [:]) {
        self.lastWarnings = lastWarnings
    }

    static func isExpiringSoon(_ expiry: Date, now: Date) -> Bool {
        expiry.timeIntervalSince(now) <= warningLeadTime
    }

    mutating func shouldWarn(endpointID: UUID, expiry: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard Self.isExpiringSoon(expiry, now: now) else { return false }
        if let last = lastWarnings[endpointID], calendar.isDate(last, inSameDayAs: now) {
            return false
        }
        lastWarnings[endpointID] = now
        return true
    }

    mutating func forget(endpointID: UUID) {
        lastWarnings[endpointID] = nil
    }

    static func daysRemaining(until expiry: Date, now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiry)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
