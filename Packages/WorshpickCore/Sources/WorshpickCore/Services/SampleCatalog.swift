import Foundation

/// Fifteen invented songs used by the tests and by the app's debug "load sample catalog" command.
public enum SampleCatalog {
    private struct SampleSong: Decodable {
        var title: String
        var artist: String
        var language: SongLanguage
        var lyrics: String
        var summary: String
        var keywords: [String]
        var invitations: [String]
        var themes: [String]
        var moments: [String]
        var energy: Energy
        var passages: [String]
    }

    public static func analyzedSongs() throws -> [AnalyzedSong] {
        let url = Bundle.module.url(forResource: "sample-catalog", withExtension: "json")!
        return try JSONDecoder().decode([SampleSong].self, from: Data(contentsOf: url)).map { sample in
            AnalyzedSong(
                title: sample.title, artist: sample.artist, language: sample.language, lyrics: sample.lyrics,
                summary: sample.summary, keywords: sample.keywords, invitations: sample.invitations,
                themes: sample.themes, moments: sample.moments, energy: sample.energy,
                passages: sample.passages.compactMap { text in
                    BibleReferenceParser.parseSingleReference(text).map { PassageDraft(reference: $0, kind: .allusion) }
                }
            )
        }
    }

    /// Adds the sample songs as ready songs without video files.
    public static func load(into catalogStore: CatalogStore) throws {
        for analyzedSong in try analyzedSongs() {
            let song = Song.pending(
                videoRelativePath: "Videos/sample/\(analyzedSong.title).mp4",
                originalFileName: "\(analyzedSong.title).mp4",
                fileHash: "sample-\(analyzedSong.title)",
                duration: 240
            )
            guard try catalogStore.song(withFileHash: song.fileHash) == nil else { continue }
            try catalogStore.insertPendingSong(song)
            try catalogStore.saveAnalyzedSong(songId: song.id, analysis: analyzedSong)
        }
    }
}
