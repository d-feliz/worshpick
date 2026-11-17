import Foundation

public struct SearchQuery: Sendable, Equatable {
    public var freeText: [String] = []
    public var exactPhrases: [String] = []
    public var authorTerms: [String] = []
    public var lyricsTerms: [String] = []
    public var themeTerms: [String] = []
    public var invitationTags: [String] = []
    public var references: [BibleReference] = []

    public init() {}

    public var hasTextTerms: Bool {
        !(freeText.isEmpty && exactPhrases.isEmpty && authorTerms.isEmpty && lyricsTerms.isEmpty && themeTerms.isEmpty)
    }

    public var isEmpty: Bool {
        !hasTextTerms && invitationTags.isEmpty && references.isEmpty
    }
}

public enum SearchQueryParser {
    private static let authorPrefixes = ["autor:", "author:", "artista:"]
    private static let lyricsPrefixes = ["letra:", "lyrics:"]
    private static let themePrefixes = ["tema:", "theme:"]

    public static func parse(_ text: String) -> SearchQuery {
        var query = SearchQuery()
        let (phrases, textWithoutPhrases) = extractQuotedPhrases(from: text)
        query.exactPhrases = phrases

        var unprefixedWords: [String] = []
        for word in textWithoutPhrases.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let value = value(of: word, afterAnyOf: authorPrefixes) {
                query.authorTerms.append(value)
            } else if let value = value(of: word, afterAnyOf: lyricsPrefixes) {
                query.lyricsTerms.append(value)
            } else if let value = value(of: word, afterAnyOf: themePrefixes) {
                query.themeTerms.append(value)
            } else if word.hasPrefix("#"), word.count > 1 {
                query.invitationTags.append(String(word.dropFirst()))
            } else {
                unprefixedWords.append(word)
            }
        }

        let parsedReferences = BibleReferenceParser.parse(unprefixedWords.joined(separator: " "))
        query.references = parsedReferences.references
        query.freeText = parsedReferences.remainingText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter(\.containsLetterOrDigit)
        return query
    }

    private static func value(of word: String, afterAnyOf prefixes: [String]) -> String? {
        let lowercasedWord = word.lowercased()
        guard let prefix = prefixes.first(where: { lowercasedWord.hasPrefix($0) }) else { return nil }
        let value = String(word.dropFirst(prefix.count))
        return value.containsLetterOrDigit ? value : nil
    }

    /// An unclosed quote is treated as plain text.
    private static func extractQuotedPhrases(from text: String) -> (phrases: [String], remainingText: String) {
        let straightQuotesText = text.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        var phrases: [String] = []
        var remainingText = ""
        var currentPhrase = ""
        var isInsideQuotes = false

        for character in straightQuotesText {
            if character == "\"" {
                if isInsideQuotes, currentPhrase.containsLetterOrDigit {
                    phrases.append(currentPhrase.trimmingCharacters(in: .whitespaces))
                }
                currentPhrase = ""
                isInsideQuotes.toggle()
                remainingText.append(" ")
            } else if isInsideQuotes {
                currentPhrase.append(character)
            } else {
                remainingText.append(character)
            }
        }
        if isInsideQuotes {
            remainingText.append(" " + currentPhrase)
        }
        return (phrases, remainingText)
    }
}
