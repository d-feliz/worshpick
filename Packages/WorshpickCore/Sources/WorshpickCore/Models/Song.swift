import Foundation
import GRDB

public struct Song: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord, StoresUUIDsAsText {
    public static let databaseTableName = "song"

    public static let needsReviewConfidenceThreshold = 0.6

    public var id: UUID
    public var videoRelativePath: String
    public var originalFileName: String
    public var fileHash: String
    public var duration: Double
    public var importedAt: Date

    public var title: String
    public var artist: String
    public var language: SongLanguage?
    public var lyrics: String
    public var summary: String
    public var keywords: [String]
    public var invitations: [String]
    public var themes: [String]
    public var moments: [String]
    public var energy: Energy?

    public var ocrEngine: OCREngineKind?
    public var ocrConfidence: Double?
    public var ocrText: String?

    public var status: SongStatus
    public var failureReason: String?
    public var manuallyEditedFields: Set<EditableSongField>

    public var needsReview: Bool {
        guard let ocrConfidence else { return false }
        return ocrConfidence < Self.needsReviewConfidenceThreshold
    }

    public static func pending(
        id: UUID = UUID(),
        videoRelativePath: String,
        originalFileName: String,
        fileHash: String,
        duration: Double,
        importedAt: Date = .now
    ) -> Song {
        Song(
            id: id,
            videoRelativePath: videoRelativePath,
            originalFileName: originalFileName,
            fileHash: fileHash,
            duration: duration,
            importedAt: importedAt,
            title: (originalFileName as NSString).deletingPathExtension,
            artist: "",
            language: nil,
            lyrics: "",
            summary: "",
            keywords: [],
            invitations: [],
            themes: [],
            moments: [],
            energy: nil,
            ocrEngine: nil,
            ocrConfidence: nil,
            ocrText: nil,
            status: .pending,
            failureReason: nil,
            manuallyEditedFields: []
        )
    }
}
