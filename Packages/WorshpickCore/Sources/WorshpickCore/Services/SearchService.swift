import Foundation
import GRDB

/// Search reads only SQLite: no AI, instant, and it works offline.
public final class SearchService: Sendable {
    public static let snippetHighlightStart = "⟦"
    public static let snippetHighlightEnd = "⟧"
    public static let defaultResultLimit = 200

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func search(
        _ text: String,
        filters: SearchFilters = SearchFilters(),
        today: Date = .now,
        limit: Int = defaultResultLimit
    ) throws -> [SearchResult] {
        try search(SearchQueryParser.parse(text), filters: filters, today: today, limit: limit)
    }

    public func search(
        _ query: SearchQuery,
        filters: SearchFilters = SearchFilters(),
        today: Date = .now,
        limit: Int = defaultResultLimit
    ) throws -> [SearchResult] {
        try database.writer.read { database in
            var effectiveFilters = filters
            if !query.invitationTags.isEmpty {
                let knownInvitations = try String.fetchAll(database, sql: "SELECT DISTINCT value FROM song, json_each(song.invitations)")
                for tag in query.invitationTags {
                    let matchingInvitation = knownInvitations.first { $0.normalizedForMatching == tag.normalizedForMatching }
                    effectiveFilters.invitations.insert(matchingInvitation ?? tag)
                }
            }

            let isListingEverything = query.isEmpty && effectiveFilters.isEmpty
            var conditions: [String] = []
            var arguments = StatementArguments()
            let usesFullTextSearch = query.hasTextTerms

            var sql = "SELECT song.*, "
            sql += Self.lastUsedDateSubquery + " AS lastUsedDate"
            arguments += [SetlistStatus.used.rawValue]
            if usesFullTextSearch {
                sql += ", bm25(songSearch, 10.0, 6.0, 4.0, 4.0, 3.0, 2.0, 0.0) AS rank"
                sql += ", snippet(songSearch, 5, '\(Self.snippetHighlightStart)', '\(Self.snippetHighlightEnd)', '…', 12) AS lyricsSnippet"
                sql += " FROM songSearch JOIN song ON song.id = songSearch.songId"
                conditions.append("songSearch MATCH ?")
                arguments += [Self.fullTextExpression(for: query)]
            } else {
                sql += " FROM song"
            }

            if !isListingEverything {
                conditions.append("song.status = ?")
                arguments += [SongStatus.ready.rawValue]
            }
            Self.appendReferenceCondition(for: query.references, to: &conditions, arguments: &arguments)
            Self.appendFilterConditions(for: effectiveFilters, today: today, to: &conditions, arguments: &arguments)

            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
            sql += usesFullTextSearch ? " ORDER BY rank" : " ORDER BY song.title COLLATE NOCASE"
            if !isListingEverything {
                sql += " LIMIT ?"
                arguments += [limit]
            }

            let rows = try Row.fetchAll(database, sql: sql, arguments: arguments)
            let songs = try rows.map { try Song(row: $0) }
            let overlappingPassages = try Self.overlappingPassages(
                songIds: songs.map(\.id), references: query.references, in: database
            )

            return zip(rows, songs).map { row, song in
                SearchResult(
                    song: song,
                    matchReason: Self.matchReason(
                        for: song,
                        query: query,
                        lyricsSnippet: usesFullTextSearch ? row["lyricsSnippet"] : nil,
                        overlappingPassage: overlappingPassages[song.id]
                    ),
                    lastUsedDate: row["lastUsedDate"]
                )
            }
        }
    }

    // MARK: SQL building

    private static let lastUsedDateSubquery = """
        (SELECT MAX(setlist.serviceDate) FROM setlistItem JOIN setlist ON setlist.id = setlistItem.setlistId \
        WHERE setlistItem.songId = song.id AND setlist.status = ?)
        """

    static func fullTextExpression(for query: SearchQuery) -> String {
        var clauses: [String] = []
        clauses += query.freeText.map { prefixPhrase($0) }
        clauses += query.exactPhrases.map { quoted($0) }
        clauses += query.authorTerms.map { "artist : " + prefixPhrase($0) }
        clauses += query.lyricsTerms.map { "lyrics : " + prefixPhrase($0) }
        clauses += query.themeTerms.map { "themes : " + prefixPhrase($0) }
        return clauses.joined(separator: " AND ")
    }

    private static func quoted(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func prefixPhrase(_ term: String) -> String {
        quoted(term) + "*"
    }

    private static func appendReferenceCondition(
        for references: [BibleReference], to conditions: inout [String], arguments: inout StatementArguments
    ) {
        for reference in references {
            conditions.append("""
                EXISTS (SELECT 1 FROM passage WHERE passage.songId = song.id AND passage.bookId = ? \
                AND passage.startPosition <= ? AND passage.endPosition >= ?)
                """)
            arguments += [reference.bookId, reference.endPosition, reference.startPosition]
        }
    }

    private static func appendFilterConditions(
        for filters: SearchFilters, today: Date, to conditions: inout [String], arguments: inout StatementArguments
    ) {
        let jsonArrayFilters: [(column: String, values: Set<String>)] = [
            ("invitations", filters.invitations), ("themes", filters.themes), ("moments", filters.moments),
        ]
        for filter in jsonArrayFilters where !filter.values.isEmpty {
            let sortedValues = filter.values.sorted()
            conditions.append(
                "EXISTS (SELECT 1 FROM json_each(song.\(filter.column)) WHERE value IN (\(databaseQuestionMarks(count: sortedValues.count))))"
            )
            arguments += StatementArguments(sortedValues)
        }
        if !filters.energies.isEmpty {
            let energyValues = filters.energies.map(\.rawValue).sorted()
            conditions.append("song.energy IN (\(databaseQuestionMarks(count: energyValues.count)))")
            arguments += StatementArguments(energyValues)
        }
        if !filters.languages.isEmpty {
            let languageValues = filters.languages.map(\.rawValue).sorted()
            conditions.append("song.language IN (\(databaseQuestionMarks(count: languageValues.count)))")
            arguments += StatementArguments(languageValues)
        }
        if let sundayCount = filters.notUsedInLastSundays, sundayCount > 0 {
            conditions.append("""
                song.id NOT IN (SELECT setlistItem.songId FROM setlistItem JOIN setlist ON setlist.id = setlistItem.setlistId \
                WHERE setlist.status = ? AND setlist.serviceDate >= ?)
                """)
            arguments += [SetlistStatus.used.rawValue, ServiceUsageWindow.cutoffDate(sundayCount: sundayCount, relativeTo: today)]
        }
        if filters.needsReviewOnly {
            conditions.append("song.ocrConfidence < ?")
            arguments += [Song.needsReviewConfidenceThreshold]
        }
    }

    private static func overlappingPassages(
        songIds: [UUID], references: [BibleReference], in database: Database
    ) throws -> [UUID: BibleReference] {
        guard !references.isEmpty, !songIds.isEmpty else { return [:] }
        let passages = try Passage
            .filter(songIds.map(\.uuidString).contains(Column("songId")))
            .order(Column("startPosition"))
            .fetchAll(database)
        var firstOverlapBySongId: [UUID: BibleReference] = [:]
        for passage in passages where firstOverlapBySongId[passage.songId] == nil {
            if references.contains(where: { $0.overlaps(passage.reference) }) {
                firstOverlapBySongId[passage.songId] = passage.reference
            }
        }
        return firstOverlapBySongId
    }

    // MARK: Match reason

    static func matchReason(
        for song: Song, query: SearchQuery, lyricsSnippet: String?, overlappingPassage: BibleReference?
    ) -> MatchReason {
        if let overlappingPassage { return .passage(overlappingPassage) }

        let snippetHasHighlight = lyricsSnippet?.contains(snippetHighlightStart) ?? false
        let searchedLyricsExplicitly = !query.lyricsTerms.isEmpty || !query.exactPhrases.isEmpty
        if searchedLyricsExplicitly, snippetHasHighlight, let lyricsSnippet { return .lyricsSnippet(lyricsSnippet) }

        if !query.authorTerms.isEmpty { return .artist }
        if let theme = firstValue(in: song.themes, matchingAnyOf: query.themeTerms) { return .theme(theme) }

        let terms = query.freeText
        if anyWord(in: song.title, matchesAnyOf: terms) { return .title }
        if anyWord(in: song.artist, matchesAnyOf: terms) { return .artist }
        if let keyword = firstValue(in: song.keywords, matchingAnyOf: terms) { return .keyword(keyword) }
        if let theme = firstValue(in: song.themes, matchingAnyOf: terms) { return .theme(theme) }
        if anyWord(in: song.summary, matchesAnyOf: terms) { return .summary }
        if snippetHasHighlight, let lyricsSnippet { return .lyricsSnippet(lyricsSnippet) }
        return .filtersOnly
    }

    private static func anyWord(in text: String, matchesAnyOf terms: [String]) -> Bool {
        let words = text.wordsForMatching
        return terms.contains { term in
            let termWords = term.wordsForMatching
            return termWords.allSatisfy { termWord in words.contains { $0.hasPrefix(termWord) } } && !termWords.isEmpty
        }
    }

    private static func firstValue(in values: [String], matchingAnyOf terms: [String]) -> String? {
        values.first { anyWord(in: $0, matchesAnyOf: terms) }
    }
}
