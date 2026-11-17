import Foundation

extension String {
    /// Lowercased and without diacritics, so "Corazón" and "corazon" compare equal.
    public var normalizedForMatching: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }

    public var wordsForMatching: [String] {
        normalizedForMatching
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    public var containsLetterOrDigit: Bool {
        unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
