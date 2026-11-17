import Foundation
import Testing
@testable import WorshpickCore

@Suite struct CatalogStoreTests {
    @Test func savesAndReadsPendingSong() throws {
        let catalog = try TestCatalog()
        let songId = try catalog.addPendingSong(fileName: "Mi Canción.mp4", fileHash: "abc")
        let song = try #require(try catalog.catalogStore.song(id: songId))
        #expect(song.title == "Mi Canción")
        #expect(try catalog.catalogStore.song(withFileHash: "abc")?.id == songId)
    }

    @Test func analyzedSongBecomesReadyAndSearchable() throws {
        let catalog = try TestCatalog()
        let songId = try catalog.addReadySong(.sample(title: "Refugio Eterno", lyrics: "montaña segura"))
        #expect(try catalog.catalogStore.song(id: songId)?.status == .ready)
        #expect(catalog.titles(for: try catalog.searchService.search("montaña")) == ["Refugio Eterno"])
    }

    @Test func pendingSongsAreNotInFullTextIndex() throws {
        let catalog = try TestCatalog()
        try catalog.addPendingSong(fileName: "Escondida.mp4")
        #expect(try catalog.searchService.search("Escondida").isEmpty)
    }

    @Test func reanalysisKeepsManuallyEditedFields() throws {
        let catalog = try TestCatalog()
        let songId = try catalog.addReadySong(.sample(title: "Original", invitations: ["Alegría"]))
        try catalog.catalogStore.saveManualEdit(songId: songId, edit: .invitations(["Reflexión"]))
        try catalog.catalogStore.saveAnalyzedSong(songId: songId, analysis: .sample(title: "Nuevo título", invitations: ["Celebración"]))

        let song = try #require(try catalog.catalogStore.song(id: songId))
        #expect(song.invitations == ["Reflexión"])
        #expect(song.title == "Nuevo título")
        #expect(song.manuallyEditedFields == [.invitations])
    }

    @Test func manualPassageEditSurvivesReanalysis() throws {
        let catalog = try TestCatalog()
        let romans = PassageDraft(reference: .wholeChapter(bookId: 45, chapter: 8), kind: .quote)
        let psalms = PassageDraft(reference: .wholeChapter(bookId: 19, chapter: 23), kind: .allusion)
        let songId = try catalog.addReadySong(.sample(passages: [romans]))
        try catalog.catalogStore.saveManualEdit(songId: songId, edit: .passages([psalms]))
        try catalog.catalogStore.saveAnalyzedSong(songId: songId, analysis: .sample(passages: [romans]))
        #expect(try catalog.catalogStore.passages(forSongId: songId).map(\.draft) == [psalms])
    }

    @Test func manualEditUpdatesSearchIndex() throws {
        let catalog = try TestCatalog()
        let songId = try catalog.addReadySong(.sample(title: "Viejo"))
        try catalog.catalogStore.saveManualEdit(songId: songId, edit: .title("Renombrada"))
        #expect(catalog.titles(for: try catalog.searchService.search("Renombrada")) == ["Renombrada"])
        #expect(try catalog.searchService.search("Viejo").isEmpty)
    }

    @Test func existingThemesHasNoDuplicates() throws {
        let catalog = try TestCatalog()
        try catalog.addReadySong(.sample(title: "A", themes: ["gracia", "cruz"]))
        try catalog.addReadySong(.sample(title: "B", themes: ["gracia"]))
        #expect(try catalog.catalogStore.existingThemes() == ["cruz", "gracia"])
    }

    @Test func updatesStatusAndOCRResult() throws {
        let catalog = try TestCatalog()
        let songId = try catalog.addPendingSong()
        try catalog.catalogStore.saveOCRResult(songId: songId, ocrText: "texto", engine: .vision, confidence: 0.4)
        try catalog.catalogStore.updateStatus(songId: songId, status: .failed, failureReason: "Sin texto")
        let song = try #require(try catalog.catalogStore.song(id: songId))
        #expect(song.ocrText == "texto")
        #expect(song.needsReview)
        #expect(song.status == .failed)
        #expect(song.failureReason == "Sin texto")
        #expect(try catalog.catalogStore.songs(withStatuses: [.failed]).map(\.id) == [songId])
    }

    @Test func savingUnknownSongThrows() throws {
        let catalog = try TestCatalog()
        let unknownId = UUID()
        #expect(throws: CatalogError.songNotFound(unknownId)) {
            try catalog.catalogStore.saveAnalyzedSong(songId: unknownId, analysis: .sample())
        }
    }

    @Test func deleteSongRemovesItEverywhere() throws {
        let catalog = try TestCatalog()
        let songId = try catalog.addReadySong(.sample(title: "Borrable"))
        let setlist = try catalog.setlistStore.createSetlist(serviceDate: .now)
        try catalog.setlistStore.addSong(songId, to: setlist.id)
        try catalog.catalogStore.deleteSong(id: songId)
        #expect(try catalog.catalogStore.song(id: songId) == nil)
        #expect(try catalog.searchService.search("Borrable").isEmpty)
        #expect(try catalog.setlistStore.setlist(id: setlist.id)?.items.isEmpty == true)
    }
}
