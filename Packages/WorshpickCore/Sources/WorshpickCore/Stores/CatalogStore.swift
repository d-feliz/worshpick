import Foundation
import GRDB

public enum CatalogError: Error, Equatable {
    case songNotFound(UUID)
}

public final class CatalogStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: Reading

    public func song(id: UUID) throws -> Song? {
        try database.writer.read { database in try Self.fetchSong(id: id, in: database) }
    }

    public func song(withFileHash fileHash: String) throws -> Song? {
        try database.writer.read { database in
            try Song.filter(Column("fileHash") == fileHash).fetchOne(database)
        }
    }

    public func allSongs() throws -> [Song] {
        try database.writer.read { database in
            try Song.order(Column("title").collating(.localizedCaseInsensitiveCompare)).fetchAll(database)
        }
    }

    public func songs(withStatuses statuses: Set<SongStatus>) throws -> [Song] {
        try database.writer.read { database in
            try Song
                .filter(statuses.map(\.rawValue).contains(Column("status")))
                .order(Column("importedAt"))
                .fetchAll(database)
        }
    }

    public func passages(forSongId songId: UUID) throws -> [Passage] {
        try database.writer.read { database in
            try Passage.filter(Column("songId") == songId.uuidString).order(Column("startPosition")).fetchAll(database)
        }
    }

    public func existingThemes() throws -> [String] {
        try distinctValues(ofJSONArrayColumn: "themes")
    }

    public func existingInvitations() throws -> [String] {
        try distinctValues(ofJSONArrayColumn: "invitations")
    }

    private func distinctValues(ofJSONArrayColumn column: String) throws -> [String] {
        try database.writer.read { database in
            try String.fetchAll(database, sql: """
                SELECT DISTINCT value FROM song, json_each(song.\(column)) ORDER BY value COLLATE NOCASE
                """)
        }
    }

    // MARK: Writing

    public func insertPendingSong(_ song: Song) throws {
        try database.writer.write { database in try song.insert(database) }
    }

    public func deleteSong(id: UUID) throws {
        try database.writer.write { database in
            try database.execute(sql: "DELETE FROM songSearch WHERE songId = ?", arguments: [id.uuidString])
            try database.execute(sql: "DELETE FROM passage WHERE songId = ?", arguments: [id.uuidString])
            try database.execute(sql: "DELETE FROM setlistItem WHERE songId = ?", arguments: [id.uuidString])
            _ = try Song.filter(Column("id") == id.uuidString).deleteAll(database)
        }
    }

    public func updateStatus(songId: UUID, status: SongStatus, failureReason: String? = nil) throws {
        try updateSong(id: songId) { song in
            song.status = status
            song.failureReason = failureReason
        }
    }

    public func saveOCRResult(songId: UUID, ocrText: String, engine: OCREngineKind, confidence: Double) throws {
        try updateSong(id: songId) { song in
            song.ocrText = ocrText
            song.ocrEngine = engine
            song.ocrConfidence = confidence
        }
    }

    /// Fields the user edited by hand keep their value, so reanalyzing never undoes a manual correction.
    public func saveAnalyzedSong(songId: UUID, analysis: AnalyzedSong) throws {
        try database.writer.write { database in
            guard var song = try Self.fetchSong(id: songId, in: database) else { throw CatalogError.songNotFound(songId) }
            let edited = song.manuallyEditedFields
            if !edited.contains(.title) { song.title = analysis.title }
            if !edited.contains(.artist) { song.artist = analysis.artist }
            if !edited.contains(.language) { song.language = analysis.language }
            if !edited.contains(.lyrics) { song.lyrics = analysis.lyrics }
            if !edited.contains(.summary) { song.summary = analysis.summary }
            if !edited.contains(.keywords) { song.keywords = analysis.keywords }
            if !edited.contains(.invitations) { song.invitations = analysis.invitations }
            if !edited.contains(.themes) { song.themes = analysis.themes }
            if !edited.contains(.moments) { song.moments = analysis.moments }
            if !edited.contains(.energy) { song.energy = analysis.energy }
            song.status = .ready
            song.failureReason = nil
            try song.update(database)
            if !edited.contains(.passages) {
                try Self.replacePassages(songId: songId, with: analysis.passages, in: database)
            }
            try Self.refreshSearchIndex(for: song, in: database)
        }
    }

    public func saveManualEdit(songId: UUID, edit: ManualSongEdit) throws {
        try database.writer.write { database in
            guard var song = try Self.fetchSong(id: songId, in: database) else { throw CatalogError.songNotFound(songId) }
            switch edit {
            case .title(let title): song.title = title
            case .artist(let artist): song.artist = artist
            case .language(let language): song.language = language
            case .lyrics(let lyrics): song.lyrics = lyrics
            case .summary(let summary): song.summary = summary
            case .keywords(let keywords): song.keywords = keywords
            case .invitations(let invitations): song.invitations = invitations
            case .themes(let themes): song.themes = themes
            case .moments(let moments): song.moments = moments
            case .energy(let energy): song.energy = energy
            case .passages(let passages): try Self.replacePassages(songId: songId, with: passages, in: database)
            }
            song.manuallyEditedFields.insert(edit.field)
            try song.update(database)
            try Self.refreshSearchIndex(for: song, in: database)
        }
    }

    // MARK: Private

    private func updateSong(id: UUID, _ change: @Sendable (inout Song) -> Void) throws {
        try database.writer.write { database in
            guard var song = try Self.fetchSong(id: id, in: database) else { throw CatalogError.songNotFound(id) }
            change(&song)
            try song.update(database)
        }
    }

    private static func fetchSong(id: UUID, in database: Database) throws -> Song? {
        try Song.filter(Column("id") == id.uuidString).fetchOne(database)
    }

    private static func replacePassages(songId: UUID, with drafts: [PassageDraft], in database: Database) throws {
        try database.execute(sql: "DELETE FROM passage WHERE songId = ?", arguments: [songId.uuidString])
        for draft in drafts {
            var passage = Passage(songId: songId, draft: draft)
            try passage.insert(database)
        }
    }

    private static func refreshSearchIndex(for song: Song, in database: Database) throws {
        try database.execute(sql: "DELETE FROM songSearch WHERE songId = ?", arguments: [song.id.uuidString])
        guard song.status == .ready else { return }
        try database.execute(
            sql: """
                INSERT INTO songSearch (title, artist, keywords, themes, summary, lyrics, songId)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                song.title, song.artist, song.keywords.joined(separator: " "), song.themes.joined(separator: " "),
                song.summary, song.lyrics, song.id.uuidString,
            ]
        )
    }
}
