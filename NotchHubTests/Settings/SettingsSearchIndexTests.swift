import Foundation
import Testing
@testable import NotchHub

struct SettingsSearchNormalizerTests {
    @Test(arguments: [
        ("İZİN", "izin"),
        ("ışık", "isik"),
        ("IŞIK", "isik"),
        ("Kulaklık", "kulaklik"),
        ("ÇENTİK", "centik"),
        ("Göstergeler", "gostergeler"),
        ("  Ağ   ve\tVPN ", "ag ve vpn"),
        ("Container’ları", "container'lari"),
    ])
    func foldsCaseDiacriticsAndTurkishLetters(input: String, expected: String) {
        #expect(SettingsSearchNormalizer.normalize(input) == expected)
    }

    @Test func blankQueryHasNoTokens() {
        #expect(SettingsSearchNormalizer.tokens(of: "   ").isEmpty)
        #expect(SettingsSearchNormalizer.tokens(of: "Pil  Şarj") == ["pil", "sarj"])
    }
}

struct SettingsSearchIndexTests {
    private func categories(for query: String) -> [SettingsCategory] {
        SettingsSearchIndex.search(query).map(\.category)
    }

    @Test func blankQueryListsEveryCategoryWithoutMatches() {
        let results = SettingsSearchIndex.search("")
        #expect(results.map(\.category) == SettingsCategory.allCases)
        #expect(results.allSatisfy { $0.matchedItems.isEmpty })
    }

    @Test func indexHasOneEntryPerCategoryInOrder() {
        #expect(SettingsSearchIndex.entries.map(\.category) == SettingsCategory.allCases)
    }

    @Test(arguments: SettingsCategory.allCases)
    func noCategoryIsEmpty(category: SettingsCategory) {
        let entry = SettingsSearchIndex.entry(for: category)
        #expect(!entry.items.isEmpty)
        #expect(!entry.synonyms.isEmpty)
        #expect(entry.items.allSatisfy { !$0.turkish.isEmpty && !$0.english.isEmpty })
    }

    @Test(arguments: SettingsCategory.allCases)
    func everyCategoryIsReachableByItsTitleInBothLanguages(category: SettingsCategory) {
        let title = SettingsSearchIndex.entry(for: category).title
        #expect(categories(for: title.turkish).contains(category))
        #expect(categories(for: title.english).contains(category))
    }

    @Test(arguments: SettingsCategory.allCases)
    func everyItemLeadsToItsCategory(category: SettingsCategory) {
        for item in SettingsSearchIndex.entry(for: category).items {
            #expect(categories(for: item.turkish).contains(category), "\(item.turkish)")
            #expect(categories(for: item.english).contains(category), "\(item.english)")
        }
    }

    @Test(arguments: SettingsCategory.allCases)
    func indexTitleMatchesTheSidebarTitle(category: SettingsCategory) {
        // Tests run in Turkish, the source language, so the resolved title is the key.
        #expect(SettingsSearchIndex.entry(for: category).title.turkish == String(localized: category.title))
    }

    @Test(arguments: SettingsCategory.allCases)
    func everyCategoryHasALocalizableSubtitle(category: SettingsCategory) {
        #expect(!String(localized: category.subtitle).isEmpty)
    }

    @Test(arguments: [
        ("ses", SettingsCategory.hud),
        ("volume", .hud),
        ("pil", .battery),
        ("whatsapp", .notifications),
        ("airpods", .headphones),
        ("pomodoro", .timer),
        ("zoom", .meeting),
        ("ollama", .devOps),
        ("anydesk", .remoteSession),
        ("csv", .timeTracking),
        ("wifi", .network),
        ("kısayol", .shortcuts),
        ("pano", .shelf),
        ("spotify", .media),
    ])
    func synonymsLeadToTheirCategory(query: String, expected: SettingsCategory) {
        #expect(categories(for: query).contains(expected))
    }

    @Test func matchingIsCaseDiacriticAndTurkishInsensitive() {
        for query in ["KULAKLIK", "kulaklik", "Kulaklık", "kulaklık"] {
            #expect(categories(for: query).contains(.headphones), "\(query)")
        }
        #expect(categories(for: "IZNI").contains(.notifications))
        #expect(categories(for: "erişilebilirlik İZNİ").contains(.unread))
    }

    @Test func englishLabelsAreSearchable() {
        #expect(categories(for: "Launch at Login") == [.general])
        #expect(categories(for: "hover delay").contains(.notch))
        #expect(categories(for: "Notifications").contains(.notifications))
    }

    @Test func showsAtMostThreeMatchedItemsInPageOrder() throws {
        let result = try #require(SettingsSearchIndex.search("ekran").first { $0.category == .automations })
        #expect(result.matchedItems.count == SettingsSearchIndex.maxMatchedItems)
        #expect(result.matchedItems.first?.turkish == "Ekran Görüntüleri ve İndirilenler")
    }

    @Test func synonymOnlyMatchShowsNoItems() throws {
        let result = try #require(SettingsSearchIndex.search("airpods").first { $0.category == .headphones })
        #expect(result.matchedItems.isEmpty)
    }

    @Test func multiWordQueryNeedsEveryWord() {
        #expect(categories(for: "düşük pil").contains(.battery))
        #expect(!categories(for: "düşük pil").contains(.performance))
    }

    @Test func unknownQueryMatchesNothing() {
        #expect(SettingsSearchIndex.search("qzxwv").isEmpty)
    }

    @Test func resultsKeepSidebarOrder() {
        let order = SettingsCategory.allCases
        let found = categories(for: "uyar")
        let indices = found.compactMap { order.firstIndex(of: $0) }
        #expect(indices == indices.sorted())
        #expect(found.count > 1)
    }
}

struct SettingsCategoryTests {
    @Test func everyGroupHasCategories() {
        for group in SettingsCategoryGroup.allCases {
            #expect(!group.categories.isEmpty)
        }
        #expect(SettingsCategoryGroup.allCases.flatMap(\.categories).count == SettingsCategory.allCases.count)
    }

    @Test func restoresPersistedSelectionWithFallback() {
        #expect(SettingsCategory.restored(from: "meeting") == .meeting)
        #expect(SettingsCategory.restored(from: "removed-page") == SettingsCategory.defaultCategory)
        #expect(SettingsCategory.restored(from: nil) == SettingsCategory.defaultCategory)
    }

    @Test func selectWritesTheSharedStorageKey() throws {
        let suiteName = "NotchHubTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsCategory.select(.calendar, in: defaults)

        #expect(SettingsCategory.restored(from: defaults.string(forKey: SettingsCategory.storageKey)) == .calendar)
    }

    @Test func iconsAreUnique() {
        let symbols = SettingsCategory.allCases.map(\.systemImage)
        #expect(Set(symbols).count == symbols.count)
    }
}
