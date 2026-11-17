import Foundation
import Testing
@testable import WorshpickCore

@Suite struct SetlistStoreTests {
    @Test func addsReordersAndRemovesItems() throws {
        let catalog = try TestCatalog.withSampleSongs()
        let store = catalog.setlistStore
        let setlist = try store.createSetlist(serviceDate: makeDate("2026-11-22"))
        let first = try store.addSong(catalog.songIdsByTitle["Fuego Santo"]!, to: setlist.id, slotLabel: "Apertura")
        let second = try store.addSong(catalog.songIdsByTitle["Mi Pastor"]!, to: setlist.id)
        let third = try store.addSong(catalog.songIdsByTitle["Limpio Estoy"]!, to: setlist.id, at: 0)

        var items = try #require(try store.setlist(id: setlist.id)).items
        #expect(items.map(\.id) == [third.id, first.id, second.id])
        #expect(items.map(\.position) == [0, 1, 2])

        try store.reorderItems(in: setlist.id, orderedItemIds: [second.id!, first.id!, third.id!])
        items = try #require(try store.setlist(id: setlist.id)).items
        #expect(items.map(\.id) == [second.id, first.id, third.id])

        try store.removeItem(id: first.id!, from: setlist.id)
        items = try #require(try store.setlist(id: setlist.id)).items
        #expect(items.map(\.id) == [second.id, third.id])
        #expect(items.map(\.position) == [0, 1])
    }

    @Test func createsSetlistWithSongs() throws {
        let catalog = try TestCatalog.withSampleSongs()
        let setlist = try catalog.setlistStore.createSetlist(
            serviceDate: .now, serviceDescription: "Romanos 8",
            songs: [(catalog.songIdsByTitle["Fuego Santo"]!, "Apertura"), (catalog.songIdsByTitle["Mi Pastor"]!, nil)]
        )
        let items = try #require(try catalog.setlistStore.setlist(id: setlist.id)).items
        #expect(items.map(\.slotLabel) == ["Apertura", nil])
    }

    @Test func draftSetlistsDoNotCountAsUsage() throws {
        let catalog = try TestCatalog.withSampleSongs()
        let songId = catalog.songIdsByTitle["Mi Pastor"]!
        let setlist = try catalog.setlistStore.createSetlist(serviceDate: makeDate("2026-11-15"))
        try catalog.setlistStore.addSong(songId, to: setlist.id)
        #expect(try catalog.setlistStore.lastUsedDateBySongId().isEmpty)
        #expect(try catalog.setlistStore.songIdsUsedInLastSundays(4, relativeTo: makeDate("2026-11-17")).isEmpty)

        try catalog.setlistStore.markAsUsed(setlistId: setlist.id)
        #expect(try catalog.setlistStore.lastUsedDateBySongId()[songId] == makeDate("2026-11-15"))
        #expect(try catalog.setlistStore.songIdsUsedInLastSundays(4, relativeTo: makeDate("2026-11-17")) == [songId])
    }

    @Test func usageWindowBoundaries() throws {
        let catalog = try TestCatalog.withSampleSongs()
        let today = makeDate("2026-11-22 08:00")
        let exactlyTwoWeeksAgo = catalog.songIdsByTitle["Mi Pastor"]!
        let justOutsideWindow = catalog.songIdsByTitle["Fuego Santo"]!
        for (songId, date) in [(exactlyTwoWeeksAgo, "2026-11-08 00:00"), (justOutsideWindow, "2026-11-07 23:59")] {
            let setlist = try catalog.setlistStore.createSetlist(serviceDate: makeDate(date))
            try catalog.setlistStore.addSong(songId, to: setlist.id)
            try catalog.setlistStore.markAsUsed(setlistId: setlist.id)
        }
        #expect(try catalog.setlistStore.songIdsUsedInLastSundays(2, relativeTo: today) == [exactlyTwoWeeksAgo])
    }
}
