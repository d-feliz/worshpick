import Foundation
import GRDB

public struct SetlistWithItems: Sendable, Hashable {
    public var setlist: Setlist
    public var items: [SetlistItem]
}

public final class SetlistStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    public func createSetlist(serviceDate: Date, serviceDescription: String = "") throws -> Setlist {
        let setlist = Setlist(serviceDate: serviceDate, serviceDescription: serviceDescription)
        try database.writer.write { database in try setlist.insert(database) }
        return setlist
    }

    @discardableResult
    public func createSetlist(serviceDate: Date, serviceDescription: String, songs: [(songId: UUID, slotLabel: String?)]) throws -> Setlist {
        let setlist = Setlist(serviceDate: serviceDate, serviceDescription: serviceDescription)
        try database.writer.write { database in
            try setlist.insert(database)
            for (position, song) in songs.enumerated() {
                var item = SetlistItem(setlistId: setlist.id, position: position, songId: song.songId, slotLabel: song.slotLabel)
                try item.insert(database)
            }
        }
        return setlist
    }

    public func allSetlists() throws -> [Setlist] {
        try database.writer.read { database in
            try Setlist.order(Column("serviceDate").desc, Column("createdAt").desc).fetchAll(database)
        }
    }

    public func setlist(id: UUID) throws -> SetlistWithItems? {
        try database.writer.read { database in
            guard let setlist = try Setlist.filter(Column("id") == id.uuidString).fetchOne(database) else { return nil }
            return SetlistWithItems(setlist: setlist, items: try Self.items(setlistId: id, in: database))
        }
    }

    public func updateDetails(setlistId: UUID, serviceDate: Date, serviceDescription: String) throws {
        try database.writer.write { database in
            try database.execute(
                sql: "UPDATE setlist SET serviceDate = ?, serviceDescription = ? WHERE id = ?",
                arguments: [serviceDate, serviceDescription, setlistId.uuidString]
            )
        }
    }

    public func deleteSetlist(id: UUID) throws {
        try database.writer.write { database in
            try database.execute(sql: "DELETE FROM setlistItem WHERE setlistId = ?", arguments: [id.uuidString])
            try database.execute(sql: "DELETE FROM setlist WHERE id = ?", arguments: [id.uuidString])
        }
    }

    @discardableResult
    public func addSong(_ songId: UUID, to setlistId: UUID, slotLabel: String? = nil, at requestedPosition: Int? = nil) throws -> SetlistItem {
        try database.writer.write { database in
            var items = try Self.items(setlistId: setlistId, in: database)
            let position = min(requestedPosition ?? items.count, items.count)
            var newItem = SetlistItem(setlistId: setlistId, position: position, songId: songId, slotLabel: slotLabel)
            try newItem.insert(database)
            items.insert(newItem, at: position)
            try Self.savePositions(of: items, in: database)
            return newItem
        }
    }

    public func removeItem(id itemId: Int64, from setlistId: UUID) throws {
        try database.writer.write { database in
            try database.execute(sql: "DELETE FROM setlistItem WHERE id = ?", arguments: [itemId])
            try Self.savePositions(of: Self.items(setlistId: setlistId, in: database), in: database)
        }
    }

    public func replaceSong(itemId: Int64, with songId: UUID) throws {
        try database.writer.write { database in
            try database.execute(sql: "UPDATE setlistItem SET songId = ? WHERE id = ?", arguments: [songId.uuidString, itemId])
        }
    }

    /// `orderedItemIds` is the full new order of the setlist.
    public func reorderItems(in setlistId: UUID, orderedItemIds: [Int64]) throws {
        try database.writer.write { database in
            let itemsById = Dictionary(uniqueKeysWithValues: try Self.items(setlistId: setlistId, in: database).compactMap { item in
                item.id.map { ($0, item) }
            })
            let reordered = orderedItemIds.compactMap { itemsById[$0] }
            try Self.savePositions(of: reordered, in: database)
        }
    }

    public func markAsUsed(setlistId: UUID) throws {
        try database.writer.write { database in
            try database.execute(sql: "UPDATE setlist SET status = ? WHERE id = ?", arguments: [SetlistStatus.used.rawValue, setlistId.uuidString])
        }
    }

    public func markAsDraft(setlistId: UUID) throws {
        try database.writer.write { database in
            try database.execute(sql: "UPDATE setlist SET status = ? WHERE id = ?", arguments: [SetlistStatus.draft.rawValue, setlistId.uuidString])
        }
    }

    // MARK: Usage history

    public func lastUsedDateBySongId() throws -> [UUID: Date] {
        try database.writer.read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT setlistItem.songId AS songId, MAX(setlist.serviceDate) AS lastUsedDate
                FROM setlistItem JOIN setlist ON setlist.id = setlistItem.setlistId
                WHERE setlist.status = ?
                GROUP BY setlistItem.songId
                """, arguments: [SetlistStatus.used.rawValue])
            var lastUsedDates: [UUID: Date] = [:]
            for row in rows {
                let songIdText: String = row["songId"]
                if let songId = UUID(uuidString: songIdText), let lastUsedDate: Date = row["lastUsedDate"] {
                    lastUsedDates[songId] = lastUsedDate
                }
            }
            return lastUsedDates
        }
    }

    public func songIdsUsedInLastSundays(_ sundayCount: Int, relativeTo today: Date, calendar: Calendar = .current) throws -> Set<UUID> {
        let cutoffDate = ServiceUsageWindow.cutoffDate(sundayCount: sundayCount, relativeTo: today, calendar: calendar)
        return try database.writer.read { database in
            let songIdTexts = try String.fetchAll(database, sql: """
                SELECT DISTINCT setlistItem.songId
                FROM setlistItem JOIN setlist ON setlist.id = setlistItem.setlistId
                WHERE setlist.status = ? AND setlist.serviceDate >= ?
                """, arguments: [SetlistStatus.used.rawValue, cutoffDate])
            return Set(songIdTexts.compactMap(UUID.init(uuidString:)))
        }
    }

    // MARK: Private

    private static func items(setlistId: UUID, in database: Database) throws -> [SetlistItem] {
        try SetlistItem.filter(Column("setlistId") == setlistId.uuidString).order(Column("position")).fetchAll(database)
    }

    private static func savePositions(of items: [SetlistItem], in database: Database) throws {
        for (position, item) in items.enumerated() {
            guard let itemId = item.id else { continue }
            try database.execute(sql: "UPDATE setlistItem SET position = ? WHERE id = ?", arguments: [position, itemId])
        }
    }
}
