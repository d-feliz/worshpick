import Foundation
import Testing
@testable import WorshpickCore

@Suite struct IngestPipelineTests {
    struct Harness {
        let catalog: TestCatalog
        let visionEngine: FakeOCREngine
        let claudeEngine: FakeOCREngine
        let analyzer: FakeSongAnalyzer
        let pipeline: IngestPipeline

        init(
            frameSampler: any FrameSampling = FakeFrameSampler(),
            visionEngine: FakeOCREngine = FakeOCREngine(),
            analyzer: FakeSongAnalyzer = FakeSongAnalyzer(),
            catalog: TestCatalog? = nil
        ) throws {
            let catalog = try catalog ?? TestCatalog()
            self.catalog = catalog
            self.visionEngine = visionEngine
            self.claudeEngine = FakeOCREngine(blocks: [OCRTextBlock(timestamp: 0, text: "Leído por Claude", confidence: 1)])
            self.analyzer = analyzer
            self.pipeline = IngestPipeline(
                catalogStore: catalog.catalogStore,
                videoURLForSong: { _ in URL(fileURLWithPath: "/dev/null") },
                frameSampler: frameSampler,
                ocrEngines: [.vision: visionEngine, .claude: claudeEngine],
                songAnalyzer: analyzer,
                settingsProvider: { IngestSettings(claudeConcurrency: 2) }
            )
        }

        func song(_ songId: UUID) throws -> Song {
            try #require(try catalog.catalogStore.song(id: songId))
        }
    }

    @Test func processesThreeSongsToReady() async throws {
        let harness = try Harness()
        let songIds = try (1...3).map { try harness.catalog.addPendingSong(fileName: "Canción \($0).mp4") }
        await harness.pipeline.enqueue(songIds: songIds)
        await harness.pipeline.waitUntilIdleOrPaused()

        for songId in songIds {
            let song = try harness.song(songId)
            #expect(song.status == .ready)
            #expect(song.ocrText == "Ni lo alto\nni lo profundo")
            #expect(song.ocrEngine == .vision)
            #expect(song.ocrConfidence == 0.9)
        }
        let progress = await harness.pipeline.currentProgress
        #expect(progress.state == .idle)
        #expect(progress.completedCount == 3)
        #expect(progress.totalCount == 3)
    }

    @Test func claudeFailureMarksOnlyThatSong() async throws {
        let analyzer = FakeSongAnalyzer([.failure(ClaudeError.invalidOutput(details: "malo")), .success(.sample(title: "Bien"))])
        let harness = try Harness(analyzer: analyzer)
        let failingId = try harness.catalog.addPendingSong(fileName: "a.mp4")
        let okId = try harness.catalog.addPendingSong(fileName: "b.mp4")
        await harness.pipeline.enqueue(songIds: [failingId])
        await harness.pipeline.waitUntilIdleOrPaused()
        await harness.pipeline.enqueue(songIds: [okId])
        await harness.pipeline.waitUntilIdleOrPaused()

        #expect(try harness.song(failingId).status == .failed)
        #expect(try harness.song(failingId).failureReason?.contains("malo") == true)
        #expect(try harness.song(okId).status == .ready)
    }

    @Test func notLoggedInPausesWithoutFailingSongs() async throws {
        let analyzer = FakeSongAnalyzer([.failure(ClaudeError.notLoggedIn(message: "expired"))])
        let harness = try Harness(analyzer: analyzer)
        let songIds = try (1...2).map { try harness.catalog.addPendingSong(fileName: "\($0).mp4") }
        await harness.pipeline.enqueue(songIds: songIds)
        await harness.pipeline.waitUntilIdleOrPaused()

        guard case .paused = await harness.pipeline.currentProgress.state else {
            Issue.record("Expected the queue to pause")
            return
        }
        #expect(try songIds.map { try harness.song($0).status }.allSatisfy { $0 != .failed && $0 != .ready })

        await harness.pipeline.resume()
        await harness.pipeline.waitUntilIdleOrPaused()
        #expect(try songIds.map { try harness.song($0).status } == [.ready, .ready])
    }

    @Test func resumesUnfinishedSongsOnLaunch() async throws {
        let harness = try Harness()
        let pendingId = try harness.catalog.addPendingSong(fileName: "pending.mp4")
        let extractingId = try harness.catalog.addPendingSong(fileName: "extracting.mp4")
        try harness.catalog.catalogStore.updateStatus(songId: extractingId, status: .extracting)
        let analyzingId = try harness.catalog.addPendingSong(fileName: "analyzing.mp4")
        try harness.catalog.catalogStore.saveOCRResult(songId: analyzingId, ocrText: "texto guardado", engine: .vision, confidence: 0.8)
        try harness.catalog.catalogStore.updateStatus(songId: analyzingId, status: .analyzing)

        try await harness.pipeline.resumeOnLaunch()
        await harness.pipeline.waitUntilIdleOrPaused()

        #expect(try [pendingId, extractingId, analyzingId].map { try harness.song($0).status } == [.ready, .ready, .ready])
        #expect(harness.visionEngine.calls == 2)
        #expect(harness.analyzer.contexts.contains { $0.ocrText == "texto guardado" })
    }

    @Test func reanalyzeDoesNotRunOCRAgain() async throws {
        let harness = try Harness()
        let songId = try harness.catalog.addPendingSong()
        await harness.pipeline.enqueue(songIds: [songId])
        await harness.pipeline.waitUntilIdleOrPaused()
        #expect(harness.visionEngine.calls == 1)

        try await harness.pipeline.reanalyze(songId: songId)
        await harness.pipeline.waitUntilIdleOrPaused()
        #expect(harness.visionEngine.calls == 1)
        #expect(harness.analyzer.contexts.count == 2)
    }

    @Test func reprocessWithClaudeOCRUsesClaudeEngine() async throws {
        let harness = try Harness()
        let songId = try harness.catalog.addPendingSong()
        try await harness.pipeline.reprocessWithClaudeOCR(songId: songId)
        await harness.pipeline.waitUntilIdleOrPaused()
        let song = try harness.song(songId)
        #expect(song.ocrEngine == .claude)
        #expect(song.ocrText == "Leído por Claude")
        #expect(harness.visionEngine.calls == 0)
    }

    @Test func manualEditsSurviveReanalysis() async throws {
        let harness = try Harness()
        let songId = try harness.catalog.addPendingSong()
        await harness.pipeline.enqueue(songIds: [songId])
        await harness.pipeline.waitUntilIdleOrPaused()
        try harness.catalog.catalogStore.saveManualEdit(songId: songId, edit: .title("Mi título"))
        try await harness.pipeline.reanalyze(songId: songId)
        await harness.pipeline.waitUntilIdleOrPaused()
        #expect(try harness.song(songId).title == "Mi título")
    }

    @Test func videoWithoutTextFailsAndNeedsReview() async throws {
        let harness = try Harness(visionEngine: FakeOCREngine(blocks: []))
        let songId = try harness.catalog.addPendingSong()
        await harness.pipeline.enqueue(songIds: [songId])
        await harness.pipeline.waitUntilIdleOrPaused()
        let song = try harness.song(songId)
        #expect(song.status == .failed)
        #expect(song.failureReason == IngestPipeline.noTextFoundReason)
        #expect(song.needsReview)
        #expect(harness.analyzer.contexts.isEmpty)
    }

    @Test func unreadableVideoFailsSong() async throws {
        let harness = try Harness(frameSampler: FakeFrameSampler(error: FrameSamplerError.unreadableVideo))
        let songId = try harness.catalog.addPendingSong()
        await harness.pipeline.enqueue(songIds: [songId])
        await harness.pipeline.waitUntilIdleOrPaused()
        #expect(try harness.song(songId).failureReason == "No se puede leer el video")
    }

    @Test func retryRequeuesFailedSong() async throws {
        let analyzer = FakeSongAnalyzer([.failure(ClaudeError.timedOut)])
        let harness = try Harness(analyzer: analyzer)
        let songId = try harness.catalog.addPendingSong()
        await harness.pipeline.enqueue(songIds: [songId])
        await harness.pipeline.waitUntilIdleOrPaused()
        #expect(try harness.song(songId).status == .failed)
        try await harness.pipeline.retry(songId: songId)
        await harness.pipeline.waitUntilIdleOrPaused()
        #expect(try harness.song(songId).status == .ready)
    }

    @Test func progressStreamReportsRunningThenIdle() async throws {
        let analyzer = FakeSongAnalyzer()
        analyzer.delay = .milliseconds(50)
        let harness = try Harness(analyzer: analyzer)
        let updates = await harness.pipeline.progressUpdates()
        let songId = try harness.catalog.addPendingSong()
        await harness.pipeline.enqueue(songIds: [songId])

        var sawRunning = false
        for await progress in updates {
            if progress.state == .running { sawRunning = true }
            if sawRunning, progress.state == .idle {
                #expect(progress.completedCount == 1)
                break
            }
        }
        #expect(sawRunning)
    }
}
