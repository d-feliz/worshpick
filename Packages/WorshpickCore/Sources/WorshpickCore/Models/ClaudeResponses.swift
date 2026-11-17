import Foundation

public enum ClaudeResponseError: Error, Equatable, LocalizedError {
    case valueOutsideVocabulary(field: String, value: String)
    case emptyField(String)

    public var errorDescription: String? {
        switch self {
        case .valueOutsideVocabulary(let field, let value): "\(field) contiene un valor no permitido: \(value)"
        case .emptyField(let field): "\(field) está vacío"
        }
    }
}

public struct SongAnalysisResponse: Decodable, Sendable, Equatable {
    public struct PassageResponse: Decodable, Sendable, Equatable {
        public var book: String
        public var chapter: Int
        public var verseStart: Int?
        public var verseEnd: Int?
        public var chapterEnd: Int?
        public var kind: PassageKind
    }

    public var title: String
    public var artist: String
    public var language: SongLanguage
    public var lyrics: String
    public var summary: String
    public var keywords: [String]
    public var invitations: [String]
    public var themes: [String]
    public var moments: [String]
    public var energy: Energy
    public var passages: [PassageResponse]

    public func validate(invitationVocabulary: [String], momentVocabulary: [String]) throws {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { throw ClaudeResponseError.emptyField("title") }
        if let invitation = invitations.first(where: { !invitationVocabulary.contains($0) }) {
            throw ClaudeResponseError.valueOutsideVocabulary(field: "invitations", value: invitation)
        }
        if let moment = moments.first(where: { !momentVocabulary.contains($0) }) {
            throw ClaudeResponseError.valueOutsideVocabulary(field: "moments", value: moment)
        }
    }

    /// Books Claude names that are not in `BibleBooks` are dropped.
    public var passageDrafts: [PassageDraft] {
        passages.compactMap { passage in
            guard let book = BibleBooks.book(named: passage.book) else { return nil }
            let start = BiblePosition.make(chapter: passage.chapter, verse: passage.verseStart ?? 1)
            let end: Int
            if let chapterEnd = passage.chapterEnd {
                end = BiblePosition.make(chapter: chapterEnd, verse: passage.verseEnd ?? BiblePosition.lastVerse)
            } else if let verseEnd = passage.verseEnd {
                end = BiblePosition.make(chapter: passage.chapter, verse: verseEnd)
            } else if passage.verseStart != nil {
                end = start
            } else {
                end = BiblePosition.make(chapter: passage.chapter, verse: BiblePosition.lastVerse)
            }
            guard start <= end else { return nil }
            return PassageDraft(reference: BibleReference(bookId: book.id, startPosition: start, endPosition: end), kind: passage.kind)
        }
    }

    public var analyzedSong: AnalyzedSong {
        AnalyzedSong(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language, lyrics: lyrics.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary, keywords: keywords, invitations: invitations,
            themes: themes.map { $0.lowercased() }, moments: moments, energy: energy, passages: passageDrafts
        )
    }
}

public struct OCRResponse: Decodable, Sendable, Equatable {
    public struct Block: Decodable, Sendable, Equatable {
        public var frameIndex: Int
        public var text: String
    }

    public var blocks: [Block]
}

public struct SuggestionResponse: Decodable, Sendable, Equatable {
    public struct Slot: Decodable, Sendable, Equatable {
        public var slotIndex: Int
        public var songId: String
        public var reason: String
        public var alternativeSongIds: [String]
    }

    public var slots: [Slot]
}
