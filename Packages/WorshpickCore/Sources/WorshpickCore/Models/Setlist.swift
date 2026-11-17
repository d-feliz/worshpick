import Foundation
import GRDB

public struct Setlist: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord, StoresUUIDsAsText {
    public static let databaseTableName = "setlist"

    public var id: UUID
    public var serviceDate: Date
    public var serviceDescription: String
    public var status: SetlistStatus
    public var createdAt: Date

    public init(id: UUID = UUID(), serviceDate: Date, serviceDescription: String, status: SetlistStatus = .draft, createdAt: Date = .now) {
        self.id = id
        self.serviceDate = serviceDate
        self.serviceDescription = serviceDescription
        self.status = status
        self.createdAt = createdAt
    }
}

public struct SetlistItem: Codable, Sendable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord, StoresUUIDsAsText {
    public static let databaseTableName = "setlistItem"

    public var id: Int64?
    public var setlistId: UUID
    public var position: Int
    public var songId: UUID
    public var slotLabel: String?

    public init(setlistId: UUID, position: Int, songId: UUID, slotLabel: String? = nil) {
        self.id = nil
        self.setlistId = setlistId
        self.position = position
        self.songId = songId
        self.slotLabel = slotLabel
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
