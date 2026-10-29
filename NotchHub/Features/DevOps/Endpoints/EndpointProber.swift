import Foundation
import Security

/// Performs one health-check request, injectable for tests.
protocol EndpointProber: Sendable {
    func probe(_ endpoint: MonitoredEndpoint) async -> EndpointProbeResult
}

/// Reads the leaf certificate's `notValidAfter` with public Security APIs (macOS only: `SecCertificateCopyValues`).
enum CertificateExpiryReader {
    static func notValidAfter(of certificate: SecCertificate) -> Date? {
        let oid = kSecOIDX509V1ValidityNotAfter
        let keys = [oid] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any],
              let entry = values[oid as String] as? [String: Any],
              let number = entry[kSecPropertyKeyValue as String] as? NSNumber
        else {
            return nil
        }
        // The value is a CFAbsoluteTime (seconds since 2001-01-01).
        return Date(timeIntervalSinceReferenceDate: number.doubleValue)
    }

    static func leafExpiry(of trust: SecTrust) -> Date? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return nil
        }
        return notValidAfter(of: leaf)
    }

    static func certificate(fromDER data: Data) -> SecCertificate? {
        SecCertificateCreateWithData(nil, data as CFData)
    }
}

/// Captures the server certificate expiry during the TLS handshake, then defers to default validation.
private final class TrustCaptureDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var expiry: Date?

    var capturedExpiry: Date? {
        lock.withLock { expiry }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let date = CertificateExpiryReader.leafExpiry(of: trust)
            lock.withLock { expiry = date }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

/// URLSession-based prober. A fresh ephemeral session per check forces a TLS handshake so expiry is always observed.
struct URLSessionEndpointProber: EndpointProber {
    static let maxTimeout: TimeInterval = 10

    func probe(_ endpoint: MonitoredEndpoint) async -> EndpointProbeResult {
        guard let url = endpoint.resolvedURL else {
            return EndpointProbeResult(errorDescription: "Geçersiz URL")
        }
        let delegate = TrustCaptureDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.timeout(for: endpoint)
        configuration.timeoutIntervalForResource = Self.timeout(for: endpoint)
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url, timeoutInterval: Self.timeout(for: endpoint))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("NotchHub-EndpointMonitor", forHTTPHeaderField: "User-Agent")

        let clock = ContinuousClock()
        let started = clock.now
        do {
            // `bytes(for:)` returns once headers arrive, so latency is time-to-first-byte and bodies are not downloaded.
            let (bytes, response) = try await session.bytes(for: request)
            bytes.task.cancel()
            let latency = Self.seconds(clock.now - started)
            let status = (response as? HTTPURLResponse)?.statusCode
            return EndpointProbeResult(statusCode: status, latency: latency, certificateExpiry: delegate.capturedExpiry)
        } catch {
            return EndpointProbeResult(
                latency: Self.seconds(clock.now - started),
                errorDescription: Self.describe(error),
                certificateExpiry: delegate.capturedExpiry
            )
        }
    }

    private static func timeout(for endpoint: MonitoredEndpoint) -> TimeInterval {
        min(maxTimeout, TimeInterval(endpoint.intervalSeconds) / 2)
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut: return "Zaman aşımı"
        case .cannotFindHost, .dnsLookupFailed: return "Sunucu bulunamadı"
        case .cannotConnectToHost: return "Bağlantı reddedildi"
        case .notConnectedToInternet: return "Çevrimdışı"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .secureConnectionFailed:
            return "TLS hatası"
        default: return urlError.localizedDescription
        }
    }
}
