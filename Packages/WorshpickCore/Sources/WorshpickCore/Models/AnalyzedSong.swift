import Foundation

public struct AnalyzedSong: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var language: SongLanguage
    public var lyrics: String
    public var summary: String
    public var keywords: [String]
    public var invitations: [String]
    public var themes: [String]
    public var moments: [String]
    public var energy: Energy
    public var passages: [PassageDraft]

    public init(
        title: String, artist: String, language: SongLanguage, lyrics: String, summary: String,
        keywords: [String], invitations: [String], themes: [String], moments: [String],
        energy: Energy, passages: [PassageDraft]
    ) {
        self.title = title
        self.artist = artist
        self.language = language
        self.lyrics = lyrics
        self.summary = summary
        self.keywords = keywords
        self.invitations = invitations
        self.themes = themes
        self.moments = moments
        self.energy = energy
        self.passages = passages
    }
}

public enum ManualSongEdit: Sendable {
    case title(String)
    case artist(String)
    case language(SongLanguage)
    case lyrics(String)
    case summary(String)
    case keywords([String])
    case invitations([String])
    case themes([String])
    case moments([String])
    case energy(Energy)
    case passages([PassageDraft])

    public var field: EditableSongField {
        switch self {
        case .title: .title
        case .artist: .artist
        case .language: .language
        case .lyrics: .lyrics
        case .summary: .summary
        case .keywords: .keywords
        case .invitations: .invitations
        case .themes: .themes
        case .moments: .moments
        case .energy: .energy
        case .passages: .passages
        }
    }
}
