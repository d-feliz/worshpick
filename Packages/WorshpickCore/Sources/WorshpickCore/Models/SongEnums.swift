import Foundation

public enum SongStatus: String, Codable, Sendable, CaseIterable {
    case pending, extracting, analyzing, ready, failed
}

public enum Energy: String, Codable, Sendable, CaseIterable {
    case high, medium, low
}

public enum SongLanguage: String, Codable, Sendable, CaseIterable {
    case es, en, other
}

public enum PassageKind: String, Codable, Sendable, CaseIterable {
    case quote, allusion
}

public enum OCREngineKind: String, Codable, Sendable, CaseIterable {
    case vision, claude
}

public enum SetlistStatus: String, Codable, Sendable, CaseIterable {
    case draft, used
}

public enum EditableSongField: String, Codable, Sendable, CaseIterable {
    case title, artist, language, lyrics, summary, keywords, invitations, themes, moments, energy, passages
}
