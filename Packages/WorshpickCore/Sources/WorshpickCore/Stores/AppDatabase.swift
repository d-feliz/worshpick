import Foundation
import GRDB

/// One SQLite database shared by every store, so search can join songs with setlist history.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    public static func onDisk(at databaseURL: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: databaseURL.path))
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.execute(sql: """
                CREATE TABLE song (
                    id TEXT PRIMARY KEY NOT NULL,
                    videoRelativePath TEXT NOT NULL,
                    originalFileName TEXT NOT NULL,
                    fileHash TEXT NOT NULL UNIQUE,
                    duration REAL NOT NULL,
                    importedAt DATETIME NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    language TEXT,
                    lyrics TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    keywords TEXT NOT NULL,
                    invitations TEXT NOT NULL,
                    themes TEXT NOT NULL,
                    moments TEXT NOT NULL,
                    energy TEXT,
                    ocrEngine TEXT,
                    ocrConfidence REAL,
                    ocrText TEXT,
                    status TEXT NOT NULL,
                    failureReason TEXT,
                    manuallyEditedFields TEXT NOT NULL
                );

                CREATE TABLE passage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    songId TEXT NOT NULL REFERENCES song(id) ON DELETE CASCADE,
                    bookId INTEGER NOT NULL,
                    startPosition INTEGER NOT NULL,
                    endPosition INTEGER NOT NULL,
                    kind TEXT NOT NULL
                );
                CREATE INDEX passage_book_range ON passage(bookId, startPosition, endPosition);
                CREATE INDEX passage_song ON passage(songId);

                CREATE TABLE setlist (
                    id TEXT PRIMARY KEY NOT NULL,
                    serviceDate DATETIME NOT NULL,
                    serviceDescription TEXT NOT NULL,
                    status TEXT NOT NULL,
                    createdAt DATETIME NOT NULL
                );

                CREATE TABLE setlistItem (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    setlistId TEXT NOT NULL REFERENCES setlist(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    songId TEXT NOT NULL REFERENCES song(id) ON DELETE CASCADE,
                    slotLabel TEXT
                );
                CREATE INDEX setlistItem_setlist ON setlistItem(setlistId, position);
                CREATE INDEX setlistItem_song ON setlistItem(songId);

                CREATE VIRTUAL TABLE songSearch USING fts5(
                    title, artist, keywords, themes, summary, lyrics,
                    songId UNINDEXED,
                    tokenize = 'unicode61 remove_diacritics 2',
                    prefix = '2 3'
                );
                """)
        }
        return migrator
    }
}
