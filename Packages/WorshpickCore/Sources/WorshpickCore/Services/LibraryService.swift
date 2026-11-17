import AVFoundation
import CryptoKit
import Foundation

public protocol FileCopying: Sendable {
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws
}

public struct FileManagerCopier: FileCopying {
    public init() {}
    public func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
}

public enum ImportOutcome: Sendable {
    case imported(Song)
    case duplicate(existing: Song)
}

public enum ImportError: Error, Equatable, LocalizedError {
    case unsupportedFileType(fileName: String)
    case copyFailed(fileName: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let fileName): "\(fileName) no es un video compatible (mp4, mov o m4v)."
        case .copyFailed(let fileName, let reason): "No se pudo copiar \(fileName): \(reason)"
        }
    }
}

/// Owns the copied videos in `<library>/Videos/<uuid>/<original name>`; the original name is what Proclaim shows on drop.
public final class LibraryService: Sendable {
    public static let supportedFileExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let videosFolderName = "Videos"
    private static let hashChunkSize = 1_048_576

    public let libraryFolder: URL
    private let catalogStore: CatalogStore
    private let fileCopier: any FileCopying

    public init(libraryFolder: URL, catalogStore: CatalogStore, fileCopier: any FileCopying = FileManagerCopier()) {
        self.libraryFolder = libraryFolder
        self.catalogStore = catalogStore
        self.fileCopier = fileCopier
    }

    public static var defaultLibraryFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Worshpick", directoryHint: .isDirectory)
    }

    public func videoURL(for song: Song) -> URL {
        libraryFolder.appending(path: song.videoRelativePath)
    }

    public func importVideo(at sourceURL: URL) async throws -> ImportOutcome {
        let fileName = sourceURL.lastPathComponent
        let isSupportedVideo = Self.supportedFileExtensions.contains(sourceURL.pathExtension.lowercased())
        guard isSupportedVideo else { throw ImportError.unsupportedFileType(fileName: fileName) }

        let fileHash = try Self.sha256Hash(of: sourceURL)
        if let existingSong = try catalogStore.song(withFileHash: fileHash) {
            return .duplicate(existing: existingSong)
        }

        let songId = UUID()
        let songFolder = libraryFolder.appending(path: Self.videosFolderName).appending(path: songId.uuidString)
        let destinationURL = songFolder.appending(path: fileName)
        do {
            try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
            try fileCopier.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: songFolder)
            throw ImportError.copyFailed(fileName: fileName, reason: error.localizedDescription)
        }

        let duration = (try? await AVURLAsset(url: destinationURL).load(.duration).seconds) ?? 0
        let song = Song.pending(
            id: songId,
            videoRelativePath: "\(Self.videosFolderName)/\(songId.uuidString)/\(fileName)",
            originalFileName: fileName,
            fileHash: fileHash,
            duration: duration.isFinite ? duration : 0
        )
        do {
            try catalogStore.insertPendingSong(song)
        } catch {
            try? FileManager.default.removeItem(at: songFolder)
            throw error
        }
        return .imported(song)
    }

    public func deleteSong(_ song: Song) throws {
        try catalogStore.deleteSong(id: song.id)
        try? FileManager.default.removeItem(at: videoURL(for: song).deletingLastPathComponent())
    }

    public func libraryDiskUsageInBytes() -> Int64 {
        let videosFolder = libraryFolder.appending(path: Self.videosFolderName)
        guard let enumerator = FileManager.default.enumerator(at: videosFolder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            totalBytes += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return totalBytes
    }

    static func sha256Hash(of fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        var hasher = SHA256()
        while let chunk = try fileHandle.read(upToCount: hashChunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
