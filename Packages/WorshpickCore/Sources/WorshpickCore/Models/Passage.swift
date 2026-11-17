import Foundation
import GRDB

/// A verse position is `chapter * 1000 + verse`, so one range comparison covers
/// whole chapters, single verses and ranges that cross chapters.
public enum BiblePosition {
    public static let lastVerse = 999

    public static func make(chapter: Int, verse: Int) -> Int {
        chapter * 1000 + verse
    }

    public static func chapter(of position: Int) -> Int { position / 1000 }
    public static func verse(of position: Int) -> Int { position % 1000 }
}

public struct BibleReference: Codable, Sendable, Hashable {
    public var bookId: Int
    public var startPosition: Int
    public var endPosition: Int

    public init(bookId: Int, startPosition: Int, endPosition: Int) {
        self.bookId = bookId
        self.startPosition = startPosition
        self.endPosition = endPosition
    }

    public static func wholeChapter(bookId: Int, chapter: Int) -> BibleReference {
        BibleReference(
            bookId: bookId,
            startPosition: BiblePosition.make(chapter: chapter, verse: 1),
            endPosition: BiblePosition.make(chapter: chapter, verse: BiblePosition.lastVerse)
        )
    }

    public func overlaps(_ other: BibleReference) -> Bool {
        bookId == other.bookId && startPosition <= other.endPosition && endPosition >= other.startPosition
    }

    public var displayText: String {
        let bookName = BibleBooks.book(id: bookId)?.spanishName ?? "Libro \(bookId)"
        let startChapter = BiblePosition.chapter(of: startPosition)
        let startVerse = BiblePosition.verse(of: startPosition)
        let endChapter = BiblePosition.chapter(of: endPosition)
        let endVerse = BiblePosition.verse(of: endPosition)
        let coversWholeChapters = startVerse == 1 && endVerse == BiblePosition.lastVerse
        if coversWholeChapters {
            return startChapter == endChapter ? "\(bookName) \(startChapter)" : "\(bookName) \(startChapter)-\(endChapter)"
        }
        if startPosition == endPosition {
            return "\(bookName) \(startChapter):\(startVerse)"
        }
        if startChapter == endChapter {
            return "\(bookName) \(startChapter):\(startVerse)-\(endVerse)"
        }
        return "\(bookName) \(startChapter):\(startVerse)-\(endChapter):\(endVerse)"
    }
}

public struct PassageDraft: Codable, Sendable, Hashable {
    public var reference: BibleReference
    public var kind: PassageKind

    public init(reference: BibleReference, kind: PassageKind) {
        self.reference = reference
        self.kind = kind
    }
}

public struct Passage: Codable, Sendable, Hashable, FetchableRecord, MutablePersistableRecord, StoresUUIDsAsText {
    public static let databaseTableName = "passage"

    public var id: Int64?
    public var songId: UUID
    public var bookId: Int
    public var startPosition: Int
    public var endPosition: Int
    public var kind: PassageKind

    public init(songId: UUID, draft: PassageDraft) {
        self.id = nil
        self.songId = songId
        self.bookId = draft.reference.bookId
        self.startPosition = draft.reference.startPosition
        self.endPosition = draft.reference.endPosition
        self.kind = draft.kind
    }

    public var reference: BibleReference {
        BibleReference(bookId: bookId, startPosition: startPosition, endPosition: endPosition)
    }

    public var draft: PassageDraft { PassageDraft(reference: reference, kind: kind) }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
