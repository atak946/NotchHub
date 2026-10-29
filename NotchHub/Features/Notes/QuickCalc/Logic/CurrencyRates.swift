import Foundation

/// Exchange rates against one base currency (USD from open.er-api.com).
struct CurrencyRates: Codable, Equatable, Sendable {
    /// ISO code every rate is quoted against.
    let base: String
    /// Units of each currency per one `base`.
    let rates: [String: Double]
    /// When the provider last updated the rates (shown as the rate date).
    let updatedAt: Date
    /// When NotchHub downloaded them (drives the cache lifetime).
    let fetchedAt: Date

    func rate(for code: String) -> Double? {
        let rate = code == base ? 1 : rates[code]
        guard let rate, rate > 0, rate.isFinite else { return nil }
        return rate
    }

    /// Converts `amount` between two ISO codes; nil when either is unknown.
    func convert(_ amount: Double, from source: String, to target: String) -> Double? {
        guard let sourceRate = rate(for: source), let targetRate = rate(for: target) else { return nil }
        return amount / sourceRate * targetRate
    }

    func isFresh(at now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) < maxAge && now >= fetchedAt
    }
}

/// Decodes the open.er-api.com `latest` payload.
enum OpenERAPIDecoder {
    enum DecodeError: Error, Equatable {
        case providerError(String)
        case malformed
    }

    private struct Payload: Decodable {
        let result: String
        let errorType: String?
        let baseCode: String?
        let timeLastUpdateUnix: TimeInterval?
        let rates: [String: Double]?

        enum CodingKeys: String, CodingKey {
            case result
            case errorType = "error-type"
            case baseCode = "base_code"
            case timeLastUpdateUnix = "time_last_update_unix"
            case rates
        }
    }

    static func decode(_ data: Data, fetchedAt: Date) throws(DecodeError) -> CurrencyRates {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw .malformed
        }
        guard payload.result == "success" else {
            throw .providerError(payload.errorType ?? payload.result)
        }
        guard let base = payload.baseCode, let rates = payload.rates, !rates.isEmpty,
              let updated = payload.timeLastUpdateUnix else {
            throw .malformed
        }
        return CurrencyRates(
            base: base,
            rates: rates,
            updatedAt: Date(timeIntervalSince1970: updated),
            fetchedAt: fetchedAt
        )
    }
}
