import Foundation

public struct SearchFilters: Sendable, Equatable {
    public var invitations: Set<String> = []
    public var themes: Set<String> = []
    public var moments: Set<String> = []
    public var energies: Set<Energy> = []
    public var languages: Set<SongLanguage> = []
    public var notUsedInLastSundays: Int?
    public var needsReviewOnly = false

    public init(
        invitations: Set<String> = [], themes: Set<String> = [], moments: Set<String> = [],
        energies: Set<Energy> = [], languages: Set<SongLanguage> = [],
        notUsedInLastSundays: Int? = nil, needsReviewOnly: Bool = false
    ) {
        self.invitations = invitations
        self.themes = themes
        self.moments = moments
        self.energies = energies
        self.languages = languages
        self.notUsedInLastSundays = notUsedInLastSundays
        self.needsReviewOnly = needsReviewOnly
    }

    public var isEmpty: Bool { self == SearchFilters() }
}

public enum MatchReason: Sendable, Equatable {
    case title
    case artist
    case keyword(String)
    case theme(String)
    case summary
    case lyricsSnippet(String)
    case passage(BibleReference)
    case filtersOnly
}

public struct SearchResult: Sendable, Identifiable {
    public var song: Song
    public var matchReason: MatchReason
    public var lastUsedDate: Date?

    public var id: UUID { song.id }
}
