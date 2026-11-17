import Foundation
import Testing
@testable import WorshpickCore

@Suite struct SuggesterTests {
    let catalog: TestCatalog

    init() throws {
        catalog = try TestCatalog.withSampleSongs()
    }

    private func songId(_ title: String) -> String { catalog.songIdsByTitle[title]!.uuidString }

    private func makeSuggester(_ runner: FakeClaudeRunner, avoidRepeats: Int = 0) -> Suggester {
        Suggester(catalogStore: catalog.catalogStore, setlistStore: catalog.setlistStore, claudeRunner: runner, settingsProvider: {
            var settings = AppSettings()
            settings.avoidRepeatsSundayCount = avoidRepeats
            settings.suggestionModel = "opus"
            return settings
        })
    }

    private func response(_ slots: [(Int, String, [String])]) -> String {
        let slotObjects = slots.map { ["slotIndex": $0.0, "songId": $0.1, "reason": "encaja", "alternativeSongIds": $0.2] as [String: Any] }
        return String(decoding: try! JSONSerialization.data(withJSONObject: ["slots": slotObjects]), as: UTF8.self)
    }

    private var request: SuggestionRequest {
        SuggestionRequest(serviceDescription: "Romanos 8: nada nos separa del amor de Dios", serviceDate: makeDate("2026-11-22"), template: .regularSunday, songCount: 5)
    }

    @Test func fillsEverySlotOfTheTemplate() async throws {
        let runner = FakeClaudeRunner([.json(response([
            (0, songId("Fuego Santo"), [songId("Shout For Joy")]),
            (1, songId("Luz en la Mañana"), []),
            (2, songId("Nada Nos Separa"), [songId("Mi Pastor")]),
            (3, songId("Bajo Sus Alas"), []),
            (4, songId("Sacrificio Vivo"), []),
        ]))])
        let draft = try await makeSuggester(runner).suggest(request)
        #expect(draft.slots.map(\.label) == ["Apertura", "Apertura", "Adoración", "Adoración", "Respuesta"])
        #expect(draft.slots.allSatisfy { $0.hasSuggestion })
        #expect(draft.slots[2].alternativeSongIds.map(\.uuidString) == [songId("Mi Pastor")])
        let sentRequest = try #require(runner.requests.first)
        #expect(sentRequest.model == "opus")
        #expect(sentRequest.prompt.contains("Romanos 8: nada nos separa"))
        let expectedSlotLine = "0: Apertura (momento: Apertura, energía: high)"
        #expect(sentRequest.prompt.contains(expectedSlotLine))
        #expect(sentRequest.prompt.contains("\"passages\":[\"Romanos 8:38-39\"]"))
    }

    @Test func recentlyUsedSongsAreNotSentToClaude() async throws {
        let usedSetlist = try catalog.setlistStore.createSetlist(serviceDate: makeDate("2026-11-15"))
        try catalog.setlistStore.addSong(catalog.songIdsByTitle["Mi Pastor"]!, to: usedSetlist.id)
        try catalog.setlistStore.markAsUsed(setlistId: usedSetlist.id)

        let runner = FakeClaudeRunner([.json(response([(0, songId("Mi Pastor"), [])]))])
        let draft = try await makeSuggester(runner, avoidRepeats: 2).suggest(request, today: makeDate("2026-11-17"))
        #expect(!(runner.requests.first?.prompt.contains(songId("Mi Pastor")) ?? true))
        #expect(draft.slots[0].songId == nil)
    }

    @Test func unknownIdIsDropped() async throws {
        let runner = FakeClaudeRunner([.json(response([(0, UUID().uuidString, []), (1, "no-es-un-id", [])]))])
        let draft = try await makeSuggester(runner).suggest(request)
        #expect(draft.slots.allSatisfy { !$0.hasSuggestion })
    }

    @Test func repeatedSongLeavesSecondSlotEmpty() async throws {
        let runner = FakeClaudeRunner([.json(response([(0, songId("Fuego Santo"), []), (1, songId("Fuego Santo"), [])]))])
        let draft = try await makeSuggester(runner).suggest(request)
        #expect(draft.slots[0].songId?.uuidString == songId("Fuego Santo"))
        #expect(draft.slots[1].songId == nil)
    }

    @Test func alternativesAreFiltered() async throws {
        let runner = FakeClaudeRunner([.json(response([
            (0, songId("Fuego Santo"), [songId("Luz en la Mañana"), UUID().uuidString]),
            (1, songId("Luz en la Mañana"), [songId("Shout For Joy"), songId("Shout For Joy")]),
        ]))])
        let draft = try await makeSuggester(runner).suggest(request)
        #expect(draft.slots[0].alternativeSongIds.isEmpty)
        #expect(draft.slots[1].alternativeSongIds.map(\.uuidString) == [songId("Shout For Joy")])
    }

    @Test func withoutTemplateCreatesNumberedSlots() async throws {
        let runner = FakeClaudeRunner([.json(response([]))])
        let draft = try await makeSuggester(runner).suggest(
            SuggestionRequest(serviceDescription: "Acción de gracias", serviceDate: .now, template: nil, songCount: 3)
        )
        #expect(draft.slots.map(\.label) == ["Canción 1", "Canción 2", "Canción 3"])
        #expect(runner.requests.first?.prompt.contains("2: Canción 3 (sin criterios)") == true)
    }

    @Test func emptyCatalogThrows() async throws {
        let emptyCatalog = try TestCatalog()
        let suggester = Suggester(catalogStore: emptyCatalog.catalogStore, setlistStore: emptyCatalog.setlistStore, claudeRunner: FakeClaudeRunner(), settingsProvider: { AppSettings() })
        await #expect(throws: SuggesterError.noCandidateSongs) { try await suggester.suggest(request) }
    }

    @Test func invalidResponseIsReported() async throws {
        let runner = FakeClaudeRunner([.json(#"{"slots": "nope"}"#)])
        await #expect {
            try await makeSuggester(runner).suggest(request)
        } throws: { error in
            if case ClaudeError.invalidOutput = error { return true }
            return false
        }
    }
}
