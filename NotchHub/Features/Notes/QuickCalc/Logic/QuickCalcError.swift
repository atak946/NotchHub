import Foundation

/// Why an input could not be evaluated. Shown muted under the input while the user types.
enum QuickCalcError: Error, Equatable, Sendable {
    case invalidNumber(String)
    case unexpectedCharacter(Character)
    case unexpectedEnd
    case unexpectedToken
    case missingClosingParenthesis
    case unmatchedClosingParenthesis
    case tooDeeplyNested
    case divisionByZero
    case invalidResult
    case unknownUnit(String)
    case incompatibleUnits
    case missingTargetUnit
    case unknownCurrency(String)
    case ratesUnavailable

    var message: String {
        switch self {
        case .invalidNumber(let raw):
            String(localized: "Geçersiz sayı: \(raw)")
        case .unexpectedCharacter(let character):
            String(localized: "Beklenmeyen karakter: \(String(character))")
        case .unexpectedEnd:
            String(localized: "İfade eksik")
        case .unexpectedToken:
            String(localized: "İfade anlaşılamadı")
        case .missingClosingParenthesis:
            String(localized: "Kapanmamış parantez")
        case .unmatchedClosingParenthesis:
            String(localized: "Fazladan kapanan parantez")
        case .tooDeeplyNested:
            String(localized: "Çok fazla iç içe parantez")
        case .divisionByZero:
            String(localized: "Sıfıra bölünemez")
        case .invalidResult:
            String(localized: "Sonuç tanımsız")
        case .unknownUnit(let word):
            String(localized: "Bilinmeyen birim: \(word)")
        case .incompatibleUnits:
            String(localized: "Bu birimler birbirine çevrilemez")
        case .missingTargetUnit:
            String(localized: "Hedef birimi yaz (ör. 5 km mil)")
        case .unknownCurrency(let code):
            String(localized: "Bilinmeyen para birimi: \(code)")
        case .ratesUnavailable:
            String(localized: "Kurlar alınamadı")
        }
    }
}
