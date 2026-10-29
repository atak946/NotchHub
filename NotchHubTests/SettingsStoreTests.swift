import Foundation
import Testing
@testable import NotchHub

@MainActor
struct SettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let (suiteName, defaults) = TestDefaults.makeSuite("SettingsStore.\(UUID().uuidString)")
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func providesDefaultsOnFirstLaunch() {
        let store = SettingsStore(defaults: makeDefaults())

        #expect(store.hoverDelay == SettingsStore.defaultHoverDelay)
        #expect(store.displayMode == .builtIn)
        #expect(store.hideInFullScreen)
        #expect(store.showOnScreensWithoutNotch)
        #expect(store.theme == .dark)
        #expect(store.enabledModules == Set(NotchModule.allCases))
        #expect(!store.isPaused)
    }

    @Test func persistsChangesAcrossInstances() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)

        store.hoverDelay = 0.3
        store.displayMode = .allScreens
        store.hideInFullScreen = false
        store.theme = .system
        store.setModule(.media, enabled: false)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.hoverDelay == 0.3)
        #expect(reloaded.displayMode == .allScreens)
        #expect(!reloaded.hideInFullScreen)
        #expect(reloaded.theme == .system)
        #expect(!reloaded.isEnabled(.media))
        #expect(reloaded.isEnabled(.shelf))
    }

    @Test func clampsOutOfRangeHoverDelay() {
        let defaults = makeDefaults()
        defaults.set(5.0, forKey: "hoverDelay")

        let store = SettingsStore(defaults: defaults)

        #expect(store.hoverDelay == SettingsStore.hoverDelayRange.upperBound)
    }

    @Test func ignoresUnknownStoredValues() {
        let defaults = makeDefaults()
        defaults.set("bogus", forKey: "displayMode")
        defaults.set(["shelf", "bogus"], forKey: "enabledModules")

        let store = SettingsStore(defaults: defaults)

        #expect(store.displayMode == .builtIn)
        #expect(store.enabledModules == [.shelf, .notes])
    }

    @Test func enablesModulesAddedAfterAnUpgrade() {
        let defaults = makeDefaults()
        defaults.set(["shelf", "media"], forKey: "enabledModules")

        let store = SettingsStore(defaults: defaults)

        #expect(store.enabledModules == [.shelf, .media, .notes])
    }

    @Test func keepsNewModuleOffOnceUserDisabledIt() {
        let defaults = makeDefaults()
        SettingsStore(defaults: defaults).setModule(.notes, enabled: false)

        let store = SettingsStore(defaults: defaults)

        #expect(!store.isEnabled(.notes))
    }

    @Test func isPausedIsNotPersisted() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.isPaused = true

        #expect(!SettingsStore(defaults: defaults).isPaused)
    }
}
