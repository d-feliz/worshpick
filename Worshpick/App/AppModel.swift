import Foundation
import Observation
import WorshpickCore

struct ImportSummary: Equatable {
    var importedCount = 0
    var duplicateFileNames: [String] = []
    var failureMessages: [String] = []

    var message: String {
        var parts = ["\(importedCount) importada\(importedCount == 1 ? "" : "s")"]
        if !duplicateFileNames.isEmpty { parts.append("\(duplicateFileNames.count) ya existía\(duplicateFileNames.count == 1 ? "" : "n")") }
        if !failureMessages.isEmpty { parts.append("\(failureMessages.count) con error") }
        return parts.joined(separator: ", ")
    }
}

/// Wires the core stores and services together for the views; one instance lives for the whole app.
@MainActor
@Observable
final class AppModel {
    let catalogStore: CatalogStore
    let setlistStore: SetlistStore
    let searchService: SearchService
    let libraryService: LibraryService
    let settingsStore: SettingsStore
    let ingestPipeline: IngestPipeline
    let suggester: Suggester
    let claudeRunner: any ClaudeRunning

    private(set) var settings: AppSettings
    private(set) var ingestProgress = IngestProgress.idle
    /// Bumped whenever songs change, so views re-run their queries.
    private(set) var catalogRevision = 0
    private(set) var setlistRevision = 0
    var currentSetlistId: UUID?
    var importSummary: ImportSummary?
    var suggestionDraft: SuggestionDraft?
    var errorMessage: String?

    init(database: AppDatabase, libraryFolder: URL, settingsFileURL: URL) {
        let settingsStore = SettingsStore(fileURL: settingsFileURL)
        let catalogStore = CatalogStore(database: database)
        let setlistStore = SetlistStore(database: database)
        let libraryService = LibraryService(libraryFolder: libraryFolder, catalogStore: catalogStore)
        let claudeRunner = SettingsAwareClaudeRunner(settingsStore: settingsStore)

        self.settingsStore = settingsStore
        self.settings = settingsStore.current
        self.catalogStore = catalogStore
        self.setlistStore = setlistStore
        self.searchService = SearchService(database: database)
        self.libraryService = libraryService
        self.claudeRunner = claudeRunner
        self.ingestPipeline = IngestPipeline(
            catalogStore: catalogStore,
            videoURLForSong: { libraryService.videoURL(for: $0) },
            frameSampler: FrameSampler(),
            ocrEngines: [
                .vision: VisionOCR(),
                .claude: ClaudeOCR(claudeRunner: claudeRunner, modelProvider: { settingsStore.current.analysisModel }),
            ],
            songAnalyzer: SongAnalyzer(claudeRunner: claudeRunner),
            settingsProvider: { settingsStore.current.ingestSettings }
        )
        self.suggester = Suggester(
            catalogStore: catalogStore, setlistStore: setlistStore, claudeRunner: claudeRunner,
            settingsProvider: { settingsStore.current }
        )
        self.currentSetlistId = try? setlistStore.allSetlists().first(where: { $0.status == .draft })?.id
    }

    static func makeLive() throws -> AppModel {
        // Lets development runs use a throwaway library instead of the real one.
        let libraryFolderOverride = ProcessInfo.processInfo.environment["WORSHPICK_LIBRARY_FOLDER"].map { URL(fileURLWithPath: $0) }
        let libraryFolder = libraryFolderOverride ?? LibraryService.defaultLibraryFolder
        let model = AppModel(
            database: try AppDatabase.onDisk(at: libraryFolder.appending(path: "catalog.sqlite")),
            libraryFolder: libraryFolder,
            settingsFileURL: libraryFolder.appending(path: "settings.json")
        )
        #if DEBUG
        if ProcessInfo.processInfo.environment["WORSHPICK_LOAD_SAMPLE_CATALOG"] == "1" {
            model.loadSampleCatalog()
        }
        DebugSnapshot.prepareDemoSetlist(in: model)
        #endif
        return model
    }

    func start() async {
        do {
            try await ingestPipeline.resumeOnLaunch()
        } catch {
            errorMessage = error.localizedDescription
        }
        for await progress in await ingestPipeline.progressUpdates() {
            ingestProgress = progress
            catalogRevision += 1
        }
    }

    func catalogDidChange() {
        catalogRevision += 1
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        perform {
            try settingsStore.update(change)
            settings = settingsStore.current
        }
    }

    // MARK: Library

    func importFiles(_ fileURLs: [URL]) async {
        var summary = ImportSummary()
        var importedSongIds: [UUID] = []
        for fileURL in fileURLs {
            let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
            defer { if hasSecurityScope { fileURL.stopAccessingSecurityScopedResource() } }
            do {
                switch try await libraryService.importVideo(at: fileURL) {
                case .imported(let song):
                    summary.importedCount += 1
                    importedSongIds.append(song.id)
                case .duplicate:
                    summary.duplicateFileNames.append(fileURL.lastPathComponent)
                }
            } catch {
                summary.failureMessages.append(error.localizedDescription)
            }
        }
        importSummary = summary
        catalogDidChange()
        await ingestPipeline.enqueue(songIds: importedSongIds)
    }

    func song(id: UUID) -> Song? {
        try? catalogStore.song(id: id)
    }

    func videoURL(for song: Song) -> URL {
        libraryService.videoURL(for: song)
    }

    func saveManualEdit(songId: UUID, _ edit: ManualSongEdit) {
        perform { try catalogStore.saveManualEdit(songId: songId, edit: edit) }
        catalogDidChange()
    }

    func deleteSong(_ song: Song) {
        perform { try libraryService.deleteSong(song) }
        catalogDidChange()
        setlistDidChange()
    }

    func reanalyze(_ songId: UUID) async {
        do { try await ingestPipeline.reanalyze(songId: songId) } catch { errorMessage = error.localizedDescription }
    }

    func reprocessWithClaudeOCR(_ songId: UUID) async {
        do { try await ingestPipeline.reprocessWithClaudeOCR(songId: songId) } catch { errorMessage = error.localizedDescription }
    }

    func retry(_ songId: UUID) async {
        do { try await ingestPipeline.retry(songId: songId) } catch { errorMessage = error.localizedDescription }
    }

    func resumeIngest() async {
        await ingestPipeline.resume()
    }

    #if DEBUG
    func loadSampleCatalog() {
        perform { try SampleCatalog.load(into: catalogStore) }
        catalogDidChange()
    }
    #endif

    // MARK: Setlists

    func setlistDidChange() {
        setlistRevision += 1
    }

    var currentSetlist: SetlistWithItems? {
        _ = setlistRevision
        guard let currentSetlistId else { return nil }
        return try? setlistStore.setlist(id: currentSetlistId)
    }

    @discardableResult
    func createSetlist(serviceDate: Date = AppModel.nextSunday(), serviceDescription: String = "") -> UUID? {
        var setlistId: UUID?
        perform { setlistId = try setlistStore.createSetlist(serviceDate: serviceDate, serviceDescription: serviceDescription).id }
        currentSetlistId = setlistId
        setlistDidChange()
        return setlistId
    }

    func addToCurrentSetlist(songIds: [UUID], at position: Int? = nil) {
        guard let setlistId = currentSetlistId ?? createSetlist() else { return }
        perform {
            for (offset, songId) in songIds.enumerated() {
                try setlistStore.addSong(songId, to: setlistId, at: position.map { $0 + offset })
            }
        }
        setlistDidChange()
    }

    func createSetlist(from draft: SuggestionDraft) {
        let filledSlots = draft.slots.compactMap { slot in slot.songId.map { (songId: $0, slotLabel: Optional(slot.label)) } }
        perform {
            let setlist = try setlistStore.createSetlist(
                serviceDate: draft.serviceDate, serviceDescription: draft.serviceDescription, songs: filledSlots
            )
            currentSetlistId = setlist.id
        }
        setlistDidChange()
    }

    func updateSetlist(_ change: (SetlistStore, UUID) throws -> Void) {
        guard let currentSetlistId else { return }
        perform { try change(setlistStore, currentSetlistId) }
        setlistDidChange()
        catalogDidChange()
    }

    static func nextSunday(after date: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let isSunday = calendar.component(.weekday, from: startOfDay) == 1
        if isSunday { return startOfDay }
        return calendar.nextDate(after: startOfDay, matching: DateComponents(weekday: 1), matchingPolicy: .nextTime) ?? startOfDay
    }
}
