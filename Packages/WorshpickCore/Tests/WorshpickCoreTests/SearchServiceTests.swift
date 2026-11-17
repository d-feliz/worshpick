import Foundation
import Testing
@testable import WorshpickCore

@Suite struct SearchServiceTests {
    let catalog: TestCatalog

    init() throws {
        catalog = try TestCatalog.withSampleSongs()
    }

    private func search(_ text: String, _ filters: SearchFilters = SearchFilters()) throws -> [SearchResult] {
        try catalog.searchService.search(text, filters: filters)
    }

    @Test func ignoresAccents() throws {
        #expect(try search("corazon").map(\.song.title).contains("Corazón Rendido"))
        #expect(try search("AGUILAS").map(\.song.title) == ["Alas Como Águilas"])
    }

    @Test func matchesPrefixes() throws {
        let titles = try search("gra").map(\.song.title)
        #expect(titles.contains("Grace Upon Grace"))
        #expect(titles.contains("Luz en la Mañana"))
    }

    @Test func titleRanksAboveLyrics() throws {
        #expect(try search("fuego").map(\.song.title) == ["Fuego Santo", "Sacrificio Vivo"])
    }

    @Test func findsByMeaningThroughKeywords() throws {
        let results = try search("perdón")
        #expect(results.map(\.song.title) == ["Limpio Estoy"])
        #expect(results.first?.matchReason == .keyword("perdón"))
    }

    @Test func findsByOverlappingPassage() throws {
        let results = try search("Romanos 8")
        #expect(results.map(\.song.title) == ["Nada Nos Separa"])
        #expect(results.first?.matchReason == .passage(BibleReference(bookId: 45, startPosition: 8038, endPosition: 8039)))
    }

    @Test func passageAndTextAreCombinedWithAnd() throws {
        #expect(try search("Salmos ruido").isEmpty)
        #expect(try search("Salmos 23 pastos").map(\.song.title) == ["Mi Pastor"])
    }

    @Test func authorPrefix() throws {
        let results = try search("autor:northfield")
        #expect(Set(results.map(\.song.title)) == ["Grace Upon Grace", "Shout For Joy", "Go Into the World"])
        #expect(results.allSatisfy { $0.matchReason == .artist })
    }

    @Test func lyricsPrefixShowsSnippet() throws {
        let results = try search("letra:fuego")
        #expect(results.map(\.song.title) == ["Sacrificio Vivo"])
        guard case .lyricsSnippet(let snippet) = results.first?.matchReason else {
            Issue.record("Expected a lyrics snippet")
            return
        }
        #expect(snippet.contains("⟦fuego⟧"))
    }

    @Test func exactPhrase() throws {
        #expect(try search("\"nada me apartará\"").map(\.song.title) == ["Nada Nos Separa"])
        #expect(try search("\"apartará nada\"").isEmpty)
    }

    @Test func themePrefixReportsTheme() throws {
        let results = try search("tema:cruz")
        #expect(Set(results.map(\.song.title)) == ["Limpio Estoy", "Mesa del Rey"])
        #expect(results.allSatisfy { $0.matchReason == .theme("cruz") })
    }

    @Test func titleMatchReason() throws {
        #expect(try search("pastor").first?.matchReason == .title)
    }

    @Test func invitationTagIgnoresAccentsAndCase() throws {
        #expect(Set(try search("#envio").map(\.song.title)) == ["Go Into the World"])
    }

    @Test func filtersUseOrWithinAndAndAcross() throws {
        let anyOfTwoInvitations = SearchFilters(invitations: ["Confianza", "Esperanza"])
        #expect(Set(try search("", anyOfTwoInvitations).map(\.song.title)) ==
                ["Nada Nos Separa", "Mi Pastor", "Alas Como Águilas", "Bajo Sus Alas"])

        var lowEnergyToo = anyOfTwoInvitations
        lowEnergyToo.energies = [.low]
        let results = try search("", lowEnergyToo)
        #expect(Set(results.map(\.song.title)) == ["Mi Pastor", "Bajo Sus Alas"])
        #expect(results.allSatisfy { $0.matchReason == .filtersOnly })
    }

    @Test func languageAndMomentFilters() throws {
        let englishClosing = SearchFilters(moments: ["Cierre"], languages: [.en])
        #expect(try search("", englishClosing).map(\.song.title) == ["Go Into the World"])
    }

    @Test func emptyQueryListsEverySongIncludingPending() throws {
        try catalog.addPendingSong(fileName: "Zeta Pendiente.mp4")
        let results = try search("")
        #expect(results.count == 16)
        #expect(results.last?.song.title == "Zeta Pendiente")
    }

    @Test func notUsedRecentlyFilterAndLastUsedDate() throws {
        let pastorId = catalog.songIdsByTitle["Mi Pastor"]!
        let setlist = try catalog.setlistStore.createSetlist(serviceDate: makeDate("2026-11-15"))
        try catalog.setlistStore.addSong(pastorId, to: setlist.id)
        try catalog.setlistStore.markAsUsed(setlistId: setlist.id)

        let withHistory = try catalog.searchService.search("pastor", today: makeDate("2026-11-17"))
        #expect(withHistory.first?.lastUsedDate == makeDate("2026-11-15"))

        let filters = SearchFilters(notUsedInLastSundays: 2)
        #expect(try catalog.searchService.search("pastor", filters: filters, today: makeDate("2026-11-17")).isEmpty)
        #expect(try catalog.searchService.search("pastor", filters: filters, today: makeDate("2026-12-20")).count == 1)
    }

    @Test func needsReviewFilter() throws {
        let pastorId = catalog.songIdsByTitle["Mi Pastor"]!
        try catalog.catalogStore.saveOCRResult(songId: pastorId, ocrText: "x", engine: .vision, confidence: 0.3)
        #expect(try search("", SearchFilters(needsReviewOnly: true)).map(\.song.title) == ["Mi Pastor"])
    }

    @Test func specialCharactersDoNotBreakQuery() throws {
        _ = try search("amor* AND OR NOT ( ) : ^")
        _ = try search("\"")
    }
}
