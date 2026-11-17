import Foundation

public struct IngestSettings: Sendable, Equatable {
    public var defaultOCREngine: OCREngineKind
    public var frameInterval: TimeInterval
    public var claudeConcurrency: Int
    public var analysisModel: String
    public var invitationVocabulary: [String]
    public var momentVocabulary: [String]

    public init(
        defaultOCREngine: OCREngineKind = .vision, frameInterval: TimeInterval = FrameSampler.defaultInterval,
        claudeConcurrency: Int = 1, analysisModel: String = "sonnet",
        invitationVocabulary: [String] = DefaultVocabularies.invitations, momentVocabulary: [String] = DefaultVocabularies.moments
    ) {
        self.defaultOCREngine = defaultOCREngine
        self.frameInterval = frameInterval
        self.claudeConcurrency = claudeConcurrency
        self.analysisModel = analysisModel
        self.invitationVocabulary = invitationVocabulary
        self.momentVocabulary = momentVocabulary
    }
}

public struct IngestProgress: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case idle
        case running
        case paused(reason: String)
    }

    public var state: State
    public var completedCount: Int
    public var totalCount: Int
    public var extractingSongIds: Set<UUID>
    public var analyzingSongIds: Set<UUID>

    public static let idle = IngestProgress(state: .idle, completedCount: 0, totalCount: 0, extractingSongIds: [], analyzingSongIds: [])
}

/// Extraction (frames + OCR) and analysis (Claude) run as two stages, so Vision reads song B while Claude analyzes song A.
public actor IngestPipeline {
    public static let noTextFoundReason = "No se encontró texto en el video"

    private struct ExtractionJob: Sendable {
        var songId: UUID
        var forcedEngine: OCREngineKind?
    }

    private let catalogStore: CatalogStore
    private let videoURLForSong: @Sendable (Song) -> URL
    private let frameSampler: any FrameSampling
    private let ocrEngines: [OCREngineKind: any OCREngine]
    private let songAnalyzer: any SongAnalyzing
    private let settingsProvider: @Sendable () -> IngestSettings

    private var extractionQueue: [ExtractionJob] = []
    private var analysisQueue: [UUID] = []
    private var extractingSongIds: Set<UUID> = []
    private var analyzingSongIds: Set<UUID> = []
    private var pauseReason: String?
    private var completedInBatch = 0
    private var totalInBatch = 0
    private var progressContinuations: [UUID: AsyncStream<IngestProgress>.Continuation] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        catalogStore: CatalogStore,
        videoURLForSong: @escaping @Sendable (Song) -> URL,
        frameSampler: any FrameSampling,
        ocrEngines: [OCREngineKind: any OCREngine],
        songAnalyzer: any SongAnalyzing,
        settingsProvider: @escaping @Sendable () -> IngestSettings
    ) {
        self.catalogStore = catalogStore
        self.videoURLForSong = videoURLForSong
        self.frameSampler = frameSampler
        self.ocrEngines = ocrEngines
        self.songAnalyzer = songAnalyzer
        self.settingsProvider = settingsProvider
    }

    // MARK: Public API

    public func enqueue(songIds: [UUID]) {
        for songId in songIds {
            addExtractionJob(ExtractionJob(songId: songId, forcedEngine: nil))
        }
        startAvailableWork()
    }

    public func resumeOnLaunch() throws {
        let unfinishedSongs = try catalogStore.songs(withStatuses: [.pending, .extracting, .analyzing])
        for song in unfinishedSongs {
            let hasOCRText = song.ocrText.map { !$0.isEmpty } ?? false
            if song.status == .analyzing, hasOCRText {
                addAnalysisJob(song.id)
            } else {
                try catalogStore.updateStatus(songId: song.id, status: .pending)
                addExtractionJob(ExtractionJob(songId: song.id, forcedEngine: nil))
            }
        }
        startAvailableWork()
    }

    public func resume() {
        pauseReason = nil
        startAvailableWork()
        publishProgress()
    }

    public func retry(songId: UUID) throws {
        try catalogStore.updateStatus(songId: songId, status: .pending)
        enqueue(songIds: [songId])
    }

    public func reanalyze(songId: UUID) throws {
        guard let song = try catalogStore.song(id: songId), let ocrText = song.ocrText, !ocrText.isEmpty else {
            try retry(songId: songId)
            return
        }
        try catalogStore.updateStatus(songId: songId, status: .analyzing)
        addAnalysisJob(songId)
        startAvailableWork()
    }

    public func reprocessWithClaudeOCR(songId: UUID) throws {
        try catalogStore.updateStatus(songId: songId, status: .pending)
        addExtractionJob(ExtractionJob(songId: songId, forcedEngine: .claude))
        startAvailableWork()
    }

    public func progressUpdates() -> AsyncStream<IngestProgress> {
        let streamId = UUID()
        let (stream, continuation) = AsyncStream<IngestProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        progressContinuations[streamId] = continuation
        continuation.yield(currentProgress)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeProgressContinuation(streamId) }
        }
        return stream
    }

    public var currentProgress: IngestProgress {
        let state: IngestProgress.State
        if let pauseReason {
            state = .paused(reason: pauseReason)
        } else if hasWorkInFlight {
            state = .running
        } else {
            state = .idle
        }
        return IngestProgress(
            state: state, completedCount: completedInBatch, totalCount: totalInBatch,
            extractingSongIds: extractingSongIds, analyzingSongIds: analyzingSongIds
        )
    }

    /// Returns when nothing is running, or when the queue is paused.
    public func waitUntilIdleOrPaused() async {
        if !hasRunningWork { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: Scheduling

    private var hasRunningWork: Bool { !extractingSongIds.isEmpty || !analyzingSongIds.isEmpty || (pauseReason == nil && hasQueuedWork) }
    private var hasQueuedWork: Bool { !extractionQueue.isEmpty || !analysisQueue.isEmpty }
    private var hasWorkInFlight: Bool { hasQueuedWork || !extractingSongIds.isEmpty || !analyzingSongIds.isEmpty }

    private func addExtractionJob(_ job: ExtractionJob) {
        let isAlreadyQueued = extractionQueue.contains { $0.songId == job.songId } || extractingSongIds.contains(job.songId)
        guard !isAlreadyQueued else { return }
        startBatchIfIdle()
        extractionQueue.append(job)
        totalInBatch += 1
    }

    private func addAnalysisJob(_ songId: UUID) {
        let isAlreadyQueued = analysisQueue.contains(songId) || analyzingSongIds.contains(songId)
        guard !isAlreadyQueued else { return }
        startBatchIfIdle()
        analysisQueue.append(songId)
        totalInBatch += 1
    }

    private func startBatchIfIdle() {
        if !hasWorkInFlight {
            completedInBatch = 0
            totalInBatch = 0
        }
    }

    private func startAvailableWork() {
        guard pauseReason == nil else {
            notifyIdleWaitersIfNeeded()
            return
        }
        if extractingSongIds.isEmpty, !extractionQueue.isEmpty {
            let job = extractionQueue.removeFirst()
            extractingSongIds.insert(job.songId)
            Task { await self.runExtraction(job) }
        }
        let concurrency = max(1, min(3, settingsProvider().claudeConcurrency))
        while analyzingSongIds.count < concurrency, !analysisQueue.isEmpty {
            let songId = analysisQueue.removeFirst()
            analyzingSongIds.insert(songId)
            Task { await self.runAnalysis(songId) }
        }
        publishProgress()
        notifyIdleWaitersIfNeeded()
    }

    // MARK: Stages

    private func runExtraction(_ job: ExtractionJob) async {
        defer {
            extractingSongIds.remove(job.songId)
            startAvailableWork()
        }
        do {
            guard let song = try catalogStore.song(id: job.songId) else { return }
            try catalogStore.updateStatus(songId: song.id, status: .extracting)
            publishProgress()

            let settings = settingsProvider()
            let engineKind = job.forcedEngine ?? settings.defaultOCREngine
            guard let engine = ocrEngines[engineKind] else { throw ClaudeError.failed(message: "Motor OCR no disponible") }

            let frames = try await frameSampler.sampleFrames(from: videoURLForSong(song), interval: settings.frameInterval)
            let blocks = try await engine.recognizeText(in: frames)
            let confidence = OCRTextBlocks.averageConfidence(of: blocks)
            try catalogStore.saveOCRResult(songId: song.id, ocrText: OCRTextBlocks.plainText(of: blocks), engine: engineKind, confidence: confidence)

            if blocks.isEmpty {
                try catalogStore.updateStatus(songId: song.id, status: .failed, failureReason: Self.noTextFoundReason)
                completedInBatch += 1
                return
            }
            try catalogStore.updateStatus(songId: song.id, status: .analyzing)
            analysisQueue.append(song.id)
        } catch let claudeError as ClaudeError where claudeError.pausesQueue {
            pause(with: claudeError)
            extractionQueue.insert(job, at: 0)
            try? catalogStore.updateStatus(songId: job.songId, status: .pending)
        } catch {
            try? catalogStore.updateStatus(songId: job.songId, status: .failed, failureReason: error.localizedDescription)
            completedInBatch += 1
        }
    }

    private func runAnalysis(_ songId: UUID) async {
        defer {
            analyzingSongIds.remove(songId)
            startAvailableWork()
        }
        do {
            guard let song = try catalogStore.song(id: songId) else { return }
            let settings = settingsProvider()
            let context = SongAnalysisContext(
                originalFileName: song.originalFileName,
                ocrText: song.ocrText ?? "",
                invitationVocabulary: settings.invitationVocabulary,
                momentVocabulary: settings.momentVocabulary,
                existingThemes: try catalogStore.existingThemes()
            )
            let analysis = try await songAnalyzer.analyze(context, model: settings.analysisModel)
            try catalogStore.saveAnalyzedSong(songId: songId, analysis: analysis)
            completedInBatch += 1
        } catch let claudeError as ClaudeError where claudeError.pausesQueue {
            pause(with: claudeError)
            analysisQueue.insert(songId, at: 0)
        } catch {
            try? catalogStore.updateStatus(songId: songId, status: .failed, failureReason: error.localizedDescription)
            completedInBatch += 1
        }
    }

    private func pause(with error: ClaudeError) {
        pauseReason = error.localizedDescription
        publishProgress()
    }

    // MARK: Progress

    private func publishProgress() {
        let progress = currentProgress
        for continuation in progressContinuations.values {
            continuation.yield(progress)
        }
    }

    private func removeProgressContinuation(_ streamId: UUID) {
        progressContinuations[streamId] = nil
    }

    private func notifyIdleWaitersIfNeeded() {
        guard !hasRunningWork else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
