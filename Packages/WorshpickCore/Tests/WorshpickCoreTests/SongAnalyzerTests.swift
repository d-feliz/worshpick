import Foundation
import Testing
@testable import WorshpickCore

@Suite struct SongAnalyzerTests {
    private let context = SongAnalysisContext(
        originalFileName: "Nada Nos Separa.mp4", ocrText: "Ni lo alto\nni lo profundo",
        invitationVocabulary: DefaultVocabularies.invitations, momentVocabulary: DefaultVocabularies.moments,
        existingThemes: ["gracia", "cruz"]
    )

    @Test func schemasAreValidJSON() throws {
        for schema in [
            ClaudeSchemas.songAnalysisSchema(invitations: DefaultVocabularies.invitations, moments: DefaultVocabularies.moments),
            ClaudeSchemas.ocrSchema, ClaudeSchemas.suggestionSchema, ClaudeSchemas.connectionTestSchema,
        ] {
            #expect(try JSONSerialization.jsonObject(with: Data(schema.utf8)) is [String: Any])
        }
    }

    @Test func analysisSchemaListsVocabulary() {
        let schema = ClaudeSchemas.songAnalysisSchema(invitations: ["Alegría", "Envío"], moments: ["Cierre"])
        #expect(schema.contains("Alegría"))
        #expect(schema.contains("Cierre"))
    }

    @Test func validResponseBecomesAnalyzedSong() async throws {
        let runner = FakeClaudeRunner([.json(SampleClaudeResponses.songAnalysis())])
        let analysis = try await SongAnalyzer(claudeRunner: runner).analyze(context, model: "sonnet")
        #expect(analysis.title == "Nada Nos Separa")
        #expect(analysis.themes == ["amor de dios", "seguridad"])
        #expect(analysis.passages == [PassageDraft(reference: BibleReference(bookId: 45, startPosition: 8038, endPosition: 8039), kind: .quote)])
        #expect(runner.requests.first?.model == "sonnet")
        #expect(runner.requests.first?.allowedTools == [])
    }

    @Test func promptIncludesExistingThemesAndOCRText() async throws {
        let runner = FakeClaudeRunner([.json(SampleClaudeResponses.songAnalysis())])
        _ = try await SongAnalyzer(claudeRunner: runner).analyze(context, model: "sonnet")
        let prompt = try #require(runner.requests.first?.prompt)
        #expect(prompt.contains("gracia, cruz"))
        #expect(prompt.contains("ni lo profundo"))
        #expect(prompt.contains("Nada Nos Separa.mp4"))
    }

    @Test func retriesOnceAfterInvalidJSON() async throws {
        let runner = FakeClaudeRunner([.json("{\"title\": 3}"), .json(SampleClaudeResponses.songAnalysis())])
        _ = try await SongAnalyzer(claudeRunner: runner).analyze(context, model: "sonnet")
        #expect(runner.requests.count == 2)
    }

    @Test func failsAfterTwoInvalidResponses() async throws {
        let outsideVocabulary = SampleClaudeResponses.songAnalysis(invitations: ["Furia"])
        let runner = FakeClaudeRunner([.json(outsideVocabulary), .json(outsideVocabulary)])
        await #expect {
            try await SongAnalyzer(claudeRunner: runner).analyze(context, model: "sonnet")
        } throws: { error in
            if case ClaudeError.invalidOutput(let details) = error { return details.contains("Furia") }
            return false
        }
        #expect(runner.requests.count == 2)
    }

    @Test func cliErrorsAreNotRetried() async throws {
        let runner = FakeClaudeRunner([.error(.notLoggedIn(message: "x"))])
        await #expect(throws: ClaudeError.notLoggedIn(message: "x")) {
            try await SongAnalyzer(claudeRunner: runner).analyze(context, model: "sonnet")
        }
        #expect(runner.requests.count == 1)
    }

    @Test func unknownBooksAreDroppedAndRangesConverted() async throws {
        let passages = """
            [{"book": "Libro Perdido", "chapter": 1, "verseStart": null, "verseEnd": null, "chapterEnd": null, "kind": "allusion"},
             {"book": "Salmos", "chapter": 23, "verseStart": null, "verseEnd": null, "chapterEnd": null, "kind": "allusion"},
             {"book": "Rom", "chapter": 8, "verseStart": 38, "verseEnd": 2, "chapterEnd": 9, "kind": "quote"},
             {"book": "Juan", "chapter": 3, "verseStart": 16, "verseEnd": null, "chapterEnd": null, "kind": "quote"},
             {"book": "Juan", "chapter": 3, "verseStart": 20, "verseEnd": 10, "chapterEnd": null, "kind": "quote"}]
            """
        let runner = FakeClaudeRunner([.json(SampleClaudeResponses.songAnalysis(passages: passages))])
        let analysis = try await SongAnalyzer(claudeRunner: runner).analyze(context, model: "sonnet")
        #expect(analysis.passages.map(\.reference) == [
            BibleReference(bookId: 19, startPosition: 23001, endPosition: 23999),
            BibleReference(bookId: 45, startPosition: 8038, endPosition: 9002),
            BibleReference(bookId: 43, startPosition: 3016, endPosition: 3016),
        ])
    }
}
