import Foundation

public struct ParsedReferences: Sendable, Equatable {
    public var references: [BibleReference]
    public var remainingText: String
}

public enum BibleReferenceParser {
    private static let longestBookNameWordCount = 5

    /// Captures "8", "8:28", "8.28", "8:28-39", "8:38-9:2" and "8-9".
    private static var chapterAndVersePattern: Regex<(Substring, Substring, Substring?, Substring?, Substring?)> { /^(\d{1,3})(?:[:.](\d{1,3}))?(?:[-–](\d{1,3})(?:[:.](\d{1,3}))?)?$/ }

    public static func parse(_ text: String) -> ParsedReferences {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var references: [BibleReference] = []
        var remainingWords: [String] = []
        var index = 0

        while index < words.count {
            if let match = referenceStarting(at: index, in: words) {
                references.append(match.reference)
                index += match.consumedWordCount
            } else {
                remainingWords.append(words[index])
                index += 1
            }
        }
        return ParsedReferences(references: references, remainingText: remainingWords.joined(separator: " "))
    }

    /// Parses a single reference such as "Romanos 8:38-39". Returns nil when the text is not exactly one reference.
    public static func parseSingleReference(_ text: String) -> BibleReference? {
        let parsed = parse(text)
        guard parsed.references.count == 1, parsed.remainingText.isEmpty else { return nil }
        return parsed.references.first
    }

    private static func referenceStarting(at startIndex: Int, in words: [String]) -> (reference: BibleReference, consumedWordCount: Int)? {
        let maximumBookWordCount = min(longestBookNameWordCount, words.count - startIndex - 1)
        guard maximumBookWordCount >= 1 else { return nil }

        for bookWordCount in stride(from: maximumBookWordCount, through: 1, by: -1) {
            let bookName = words[startIndex..<(startIndex + bookWordCount)].joined(separator: " ")
            guard let book = BibleBooks.book(named: bookName) else { continue }
            let chapterWord = words[startIndex + bookWordCount].trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            guard let reference = reference(bookId: book.id, chapterAndVerse: chapterWord) else { continue }
            return (reference, bookWordCount + 1)
        }
        return nil
    }

    private static func reference(bookId: Int, chapterAndVerse: String) -> BibleReference? {
        guard let match = chapterAndVerse.wholeMatch(of: chapterAndVersePattern),
              let startChapter = Int(match.1) else { return nil }
        let startVerse = match.2.flatMap { Int($0) }
        let rangeEnd = match.3.flatMap { Int($0) }
        let rangeEndVerse = match.4.flatMap { Int($0) }

        let lastVerse = BiblePosition.lastVerse
        let start: Int
        let end: Int
        switch (startVerse, rangeEnd, rangeEndVerse) {
        case (nil, nil, _):
            start = BiblePosition.make(chapter: startChapter, verse: 1)
            end = BiblePosition.make(chapter: startChapter, verse: lastVerse)
        case (nil, let endChapter?, let endVerse):
            start = BiblePosition.make(chapter: startChapter, verse: 1)
            end = BiblePosition.make(chapter: endChapter, verse: endVerse ?? lastVerse)
        case (let verse?, nil, _):
            start = BiblePosition.make(chapter: startChapter, verse: verse)
            end = start
        case (let verse?, let endVerseInSameChapter?, nil):
            start = BiblePosition.make(chapter: startChapter, verse: verse)
            end = BiblePosition.make(chapter: startChapter, verse: endVerseInSameChapter)
        case (let verse?, let endChapter?, let endVerse?):
            start = BiblePosition.make(chapter: startChapter, verse: verse)
            end = BiblePosition.make(chapter: endChapter, verse: endVerse)
        }
        guard start <= end else { return nil }
        return BibleReference(bookId: bookId, startPosition: start, endPosition: end)
    }
}
