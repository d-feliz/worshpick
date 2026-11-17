import Foundation
@testable import WorshpickCore

struct SampleSongFixture: Decodable {
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

    var analyzedSong: AnalyzedSong {
        AnalyzedSong(
            title: title, artist: artist, language: language, lyrics: lyrics, summary: summary,
            keywords: keywords, invitations: invitations, themes: themes, moments: moments, energy: energy,
            passages: passages.map { text in
                guard let reference = BibleReferenceParser.parseSingleReference(text) else {
                    fatalError("Fixture passage is not a valid reference: \(text)")
                }
                return PassageDraft(reference: reference, kind: .allusion)
            }
        )
    }
}

enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func sampleSongs() throws -> [SampleSongFixture] {
        try JSONDecoder().decode([SampleSongFixture].self, from: data("catalog-sample.json"))
    }
}

struct TestCatalog {
    let database: AppDatabase
    let catalogStore: CatalogStore
    let setlistStore: SetlistStore
    let searchService: SearchService
    var songIdsByTitle: [String: UUID] = [:]

    init() throws {
        database = try AppDatabase.inMemory()
        catalogStore = CatalogStore(database: database)
        setlistStore = SetlistStore(database: database)
        searchService = SearchService(database: database)
    }

    static func withSampleSongs() throws -> TestCatalog {
        var catalog = try TestCatalog()
        for fixture in try Fixtures.sampleSongs() {
            let songId = try catalog.addReadySong(fixture.analyzedSong)
            catalog.songIdsByTitle[fixture.title] = songId
        }
        return catalog
    }

    @discardableResult
    func addPendingSong(fileName: String = "video.mp4", fileHash: String = UUID().uuidString) throws -> UUID {
        let song = Song.pending(
            videoRelativePath: "Videos/x/\(fileName)", originalFileName: fileName, fileHash: fileHash, duration: 200
        )
        try catalogStore.insertPendingSong(song)
        return song.id
    }

    @discardableResult
    func addReadySong(_ analysis: AnalyzedSong) throws -> UUID {
        let songId = try addPendingSong(fileName: "\(analysis.title).mp4")
        try catalogStore.saveAnalyzedSong(songId: songId, analysis: analysis)
        return songId
    }

    func titles(for results: [SearchResult]) -> [String] {
        results.map(\.song.title)
    }
}

func makeDate(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text.count == 10 ? text + " 10:00" : text)!
}

extension AnalyzedSong {
    static func sample(
        title: String = "Canción", lyrics: String = "letra", invitations: [String] = ["Alegría"],
        themes: [String] = ["gracia"], passages: [PassageDraft] = []
    ) -> AnalyzedSong {
        AnalyzedSong(
            title: title, artist: "Artista", language: .es, lyrics: lyrics, summary: "Resumen",
            keywords: ["clave"], invitations: invitations, themes: themes, moments: ["Apertura"],
            energy: .high, passages: passages
        )
    }
}
