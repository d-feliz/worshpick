import Foundation
import Testing
@testable import WorshpickCore

@Suite struct LibraryServiceTests {
    struct FailingCopier: FileCopying {
        func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
            throw CocoaError(.fileWriteOutOfSpace)
        }
    }

    @Test func importsVideoIntoNamedFolder() async throws {
        let catalog = try TestCatalog()
        let library = LibraryService(libraryFolder: try makeTemporaryFolder(), catalogStore: catalog.catalogStore)
        guard case .imported(let song) = try await library.importVideo(at: Fixtures.url("videos/cancion-es.mp4")) else {
            Issue.record("Expected an import")
            return
        }
        let videoURL = library.videoURL(for: song)
        #expect(videoURL.lastPathComponent == "cancion-es.mp4")
        #expect(videoURL.deletingLastPathComponent().lastPathComponent == song.id.uuidString)
        #expect(FileManager.default.fileExists(atPath: videoURL.path))
        #expect(song.duration > 10)
        #expect(try catalog.catalogStore.song(id: song.id)?.status == .pending)
    }

    @Test func secondImportOfSameFileIsDuplicate() async throws {
        let catalog = try TestCatalog()
        let library = LibraryService(libraryFolder: try makeTemporaryFolder(), catalogStore: catalog.catalogStore)
        guard case .imported(let first) = try await library.importVideo(at: Fixtures.url("videos/song-en.mp4")) else {
            Issue.record("Expected an import")
            return
        }
        guard case .duplicate(let existing) = try await library.importVideo(at: Fixtures.url("videos/song-en.mp4")) else {
            Issue.record("Expected a duplicate")
            return
        }
        #expect(existing.id == first.id)
    }

    @Test func rejectsUnsupportedFileType() async throws {
        let catalog = try TestCatalog()
        let library = LibraryService(libraryFolder: try makeTemporaryFolder(), catalogStore: catalog.catalogStore)
        await #expect(throws: ImportError.unsupportedFileType(fileName: "catalog-sample.json")) {
            try await library.importVideo(at: Fixtures.url("catalog-sample.json"))
        }
    }

    @Test func failedCopyLeavesNoFolderAndNoSong() async throws {
        let catalog = try TestCatalog()
        let libraryFolder = try makeTemporaryFolder()
        let library = LibraryService(libraryFolder: libraryFolder, catalogStore: catalog.catalogStore, fileCopier: FailingCopier())
        await #expect(throws: ImportError.self) {
            try await library.importVideo(at: Fixtures.url("videos/cancion-es.mp4"))
        }
        let songFolders = (try? FileManager.default.contentsOfDirectory(atPath: libraryFolder.appending(path: "Videos").path)) ?? []
        #expect(songFolders.isEmpty)
        #expect(try catalog.catalogStore.allSongs().isEmpty)
    }

    @Test func deleteSongRemovesFiles() async throws {
        let catalog = try TestCatalog()
        let library = LibraryService(libraryFolder: try makeTemporaryFolder(), catalogStore: catalog.catalogStore)
        guard case .imported(let song) = try await library.importVideo(at: Fixtures.url("videos/cancion-es.mp4")) else { return }
        #expect(library.libraryDiskUsageInBytes() > 0)
        try library.deleteSong(song)
        #expect(!FileManager.default.fileExists(atPath: library.videoURL(for: song).path))
        #expect(library.libraryDiskUsageInBytes() == 0)
    }
}
