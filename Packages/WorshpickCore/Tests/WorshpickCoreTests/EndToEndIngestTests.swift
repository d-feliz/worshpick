import Foundation
import Testing
@testable import WorshpickCore

/// Real library, frames and Vision OCR on the fixture videos; only Claude is a fake.
@Suite struct EndToEndIngestTests {
    @Test func importsRealVideosAndMakesThemSearchable() async throws {
        let catalog = try TestCatalog()
        let library = LibraryService(libraryFolder: try makeTemporaryFolder(), catalogStore: catalog.catalogStore)
        let claudeRunner = FakeClaudeRunner([
            .json(SampleClaudeResponses.songAnalysis(title: "Nada Nos Separa")),
        ])
        let pipeline = IngestPipeline(
            catalogStore: catalog.catalogStore,
            videoURLForSong: { library.videoURL(for: $0) },
            frameSampler: FrameSampler(),
            ocrEngines: [.vision: VisionOCR()],
            songAnalyzer: SongAnalyzer(claudeRunner: claudeRunner),
            settingsProvider: { IngestSettings() }
        )

        var importedSongIds: [UUID] = []
        for videoName in ["cancion-es", "sin-texto"] {
            if case .imported(let song) = try await library.importVideo(at: Fixtures.url("videos/\(videoName).mp4")) {
                importedSongIds.append(song.id)
            }
        }
        await pipeline.enqueue(songIds: importedSongIds)
        await pipeline.waitUntilIdleOrPaused()

        let lyricSong = try #require(try catalog.catalogStore.song(id: importedSongIds[0]))
        #expect(lyricSong.status == .ready)
        #expect(lyricSong.ocrText?.normalizedForMatching.contains("nada me apartara") == true)
        let analysisPrompt = try #require(claudeRunner.requests.first?.prompt)
        #expect(analysisPrompt.normalizedForMatching.contains("tu amor me sostiene"))
        #expect(try catalog.searchService.search("Romanos 8").map(\.song.id) == [lyricSong.id])

        let plainSong = try #require(try catalog.catalogStore.song(id: importedSongIds[1]))
        #expect(plainSong.status == .failed)
        #expect(plainSong.needsReview)
        #expect(claudeRunner.requests.count == 1)
    }
}
