import Foundation
import Testing
@testable import NotchHub

@MainActor
struct ShelfRetentionTests {
    @Test func defaultsToOneDayAndPersistsChoice() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        #expect(store.retention == .oneDay)

        store.retention = .sevenDays

        #expect(fixture.makeStore().retention == .sevenDays)
    }

    @Test func ignoresUnknownStoredRetention() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set("forever", forKey: "shelf.retention")

        #expect(fixture.makeStore().retention == .oneDay)
    }

    @Test func purgesOnlyExpiredItems() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        store.retention = .oneHour
        store.add(text: "old")
        fixture.clock.advance(by: 30 * 60)
        store.add(text: "fresh")
        fixture.clock.advance(by: 30 * 60)

        store.purgeExpired()

        #expect(store.items.map(\.text) == ["fresh"])
        #expect(fixture.reloadedStore().items.map(\.text) == ["fresh"])
    }

    @Test func offKeepsEverything() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        store.retention = .off
        store.add(text: "keep")
        fixture.clock.advance(by: 365 * 24 * 3_600)

        store.purgeExpired()

        #expect(store.count == 1)
    }

    @Test func changingRetentionPurgesImmediately() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        store.retention = .sevenDays
        store.add(text: "two hours old")
        fixture.clock.advance(by: 2 * 3_600)

        store.retention = .oneHour

        #expect(store.items.isEmpty)
    }

    @Test func startPurgesItemsThatExpiredWhileQuit() throws {
        let fixture = try ShelfFixture()
        defer { fixture.cleanUp() }
        fixture.makeStore().add(text: "stale")
        fixture.clock.advance(by: 2 * 24 * 3_600)

        let store = fixture.makeStore()
        store.start()
        defer { store.stop() }

        #expect(store.items.isEmpty)
    }

    @Test func intervalsMatchTitles() {
        #expect(ShelfRetention.off.interval == nil)
        #expect(ShelfRetention.oneHour.interval == 3_600)
        #expect(ShelfRetention.oneDay.interval == 86_400)
        #expect(ShelfRetention.sevenDays.interval == 604_800)
        #expect(Set(ShelfRetention.allCases.map(\.title)).count == ShelfRetention.allCases.count)
    }
}
