import Foundation
import Testing
@testable import NotchHub

@MainActor
struct AppLanguageTests {
    private let suiteName: String
    private let suiteDefaults: UserDefaults

    init() {
        let suite = TestDefaults.makeSuite("Language.\(UUID().uuidString)")
        suiteName = suite.name
        suiteDefaults = suite.defaults
    }

    private func makeStore() -> (AppLanguageStore, UserDefaults) {
        let defaults = suiteDefaults
        defaults.removePersistentDomain(forName: suiteName)
        return (AppLanguageStore(defaults: defaults, domainName: suiteName), defaults)
    }

    private func storedLanguages(_ defaults: UserDefaults) -> [String]? {
        defaults.persistentDomain(forName: suiteName)?[AppLanguageStore.defaultsKey] as? [String]
    }

    @Test func followsTheSystemWithoutAnOverride() {
        let (store, _) = makeStore()
        #expect(store.current == .system)
    }

    @Test func selectingTurkishWritesTheOverride() {
        let (store, defaults) = makeStore()
        store.select(.turkish)
        #expect(storedLanguages(defaults) == ["tr"])
        #expect(store.current == .turkish)
    }

    @Test func selectingEnglishWritesTheOverride() {
        let (store, defaults) = makeStore()
        store.select(.english)
        #expect(storedLanguages(defaults) == ["en"])
        #expect(store.current == .english)
    }

    @Test func selectingSystemRemovesTheOverride() {
        let (store, defaults) = makeStore()
        store.select(.english)
        store.select(.system)
        #expect(storedLanguages(defaults) == nil)
        #expect(store.current == .system)
    }

    @Test(arguments: [
        ("en", AppLanguage.english),
        ("en-GB", AppLanguage.english),
        ("tr-TR", AppLanguage.turkish),
        ("de", AppLanguage.system),
    ])
    func mapsStoredIdentifiers(identifier: String, expected: AppLanguage) {
        #expect(AppLanguage(languageIdentifier: identifier) == expected)
    }

    @Test func nativeNamesStayUntranslated() {
        #expect(AppLanguage.turkish.title == "Türkçe")
        #expect(AppLanguage.english.title == "English")
        #expect(AppLanguage.system.title == "Sistem")
    }

    @Test func needsRelaunchOnlyWhenTheChoiceDiffersFromLaunch() {
        let (store, defaults) = makeStore()
        store.select(.turkish)
        let settings = AppLanguageSettings(store: store)
        #expect(settings.launchLanguage == .turkish)
        #expect(!settings.needsRelaunch)

        settings.selection = .english
        #expect(settings.needsRelaunch)
        #expect(storedLanguages(defaults) == ["en"])

        settings.selection = .turkish
        #expect(!settings.needsRelaunch)
    }

    @Test func relaunchPassesTheBundlePathAsAnArgument() {
        let path = "/Applications/Notch Hub's \"Test\".app"
        let arguments = AppRelauncher.arguments(bundlePath: path)
        #expect(arguments == ["-c", AppRelauncher.script, path])
        #expect(AppRelauncher.script.contains("sleep 1"))
        #expect(AppRelauncher.script.contains("/usr/bin/open -n"))
    }
}
