import Foundation

/// Folds text for settings search: case-, diacritic- and width-insensitive, and Turkish-aware so
/// "İ", "I", "ı" and "i" all compare equal ("ışık", "IŞIK" and "isik" match each other).
enum SettingsSearchNormalizer {
    private static let foldingLocale = Locale(identifier: "en_US_POSIX")
    private static let foldingOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    static func normalize(_ text: String) -> String {
        let dotless = text
            .replacingOccurrences(of: "İ", with: "i")
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "’", with: "'")
        let folded = dotless.folding(options: foldingOptions, locale: foldingLocale)
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Normalized words of a query; empty when the query is blank.
    static func tokens(of query: String) -> [String] {
        normalize(query).split(separator: " ").map(String.init)
    }
}

/// A searchable label: the Turkish source key and its English translation.
struct SettingsSearchTerm: Hashable, Sendable {
    let turkish: String
    let english: String
    private let normalizedTurkish: String
    private let normalizedEnglish: String

    init(_ turkish: String, _ english: String) {
        self.turkish = turkish
        self.english = english
        normalizedTurkish = SettingsSearchNormalizer.normalize(turkish)
        normalizedEnglish = SettingsSearchNormalizer.normalize(english)
    }

    /// True when every token occurs in the Turkish or in the English text.
    func matches(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy(normalizedTurkish.contains) || tokens.allSatisfy(normalizedEnglish.contains)
    }

    /// The label in the app's current language.
    func displayText(isEnglish: Bool) -> String {
        isEnglish ? english : turkish
    }
}

/// Everything one settings page can be found by.
struct SettingsSearchEntry: Sendable {
    let category: SettingsCategory
    let title: SettingsSearchTerm
    /// Section titles and control labels shown on the page, in page order.
    let items: [SettingsSearchTerm]
    /// Extra words (both languages) that should lead to the page; never shown to the user.
    let synonyms: [String]
    private let normalizedSynonyms: [String]

    init(category: SettingsCategory, title: SettingsSearchTerm, items: [SettingsSearchTerm], synonyms: [String]) {
        self.category = category
        self.title = title
        self.items = items
        self.synonyms = synonyms
        normalizedSynonyms = synonyms.map(SettingsSearchNormalizer.normalize)
    }

    func matchesSynonym(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        return normalizedSynonyms.contains { synonym in tokens.allSatisfy(synonym.contains) }
    }
}

struct SettingsSearchResult: Identifiable, Equatable, Sendable {
    let category: SettingsCategory
    /// Up to `SettingsSearchIndex.maxMatchedItems` matching labels on the page.
    let matchedItems: [SettingsSearchTerm]

    var id: SettingsCategory { category }
}

/// Static index of every settings page; filters the sidebar while searching.
enum SettingsSearchIndex {
    static let maxMatchedItems = 3

    static let entries: [SettingsSearchEntry] = SettingsCategory.allCases.map(SettingsSearchCatalog.entry(for:))

    static func entry(for category: SettingsCategory) -> SettingsSearchEntry {
        SettingsSearchCatalog.entry(for: category)
    }

    /// Matching pages in sidebar order. A blank query returns every page without matched items.
    static func search(_ query: String) -> [SettingsSearchResult] {
        let tokens = SettingsSearchNormalizer.tokens(of: query)
        guard !tokens.isEmpty else {
            return entries.map { SettingsSearchResult(category: $0.category, matchedItems: []) }
        }
        return entries.compactMap { result(for: $0, tokens: tokens) }
    }

    private static func result(for entry: SettingsSearchEntry, tokens: [String]) -> SettingsSearchResult? {
        let items = entry.items.filter { $0.matches(tokens) }
        guard !items.isEmpty || entry.title.matches(tokens) || entry.matchesSynonym(tokens) else { return nil }
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.turkish).inserted }
        return SettingsSearchResult(category: entry.category, matchedItems: Array(unique.prefix(maxMatchedItems)))
    }
}

/// Maps each page to its terms (defined in SettingsSearchCatalog+Entries.swift).
enum SettingsSearchCatalog {
    static func entry(for category: SettingsCategory) -> SettingsSearchEntry {
        switch category {
        case .general: general
        case .notch: notch
        case .hud: hud
        case .alerts: alerts
        case .shelf: shelf
        case .media: media
        case .timer: timer
        case .calendar: calendar
        case .notes: notes
        case .weather: weather
        case .battery: battery
        case .notifications: notifications
        case .unread: unread
        case .meeting: meeting
        case .network: network
        case .headphones: headphones
        case .performance: performance
        case .remoteSession: remoteSession
        case .devOps: devOps
        case .profiles: profiles
        case .integrations: integrations
        case .shortcuts: shortcuts
        case .automations: automations
        case .timeTracking: timeTracking
        }
    }
}
