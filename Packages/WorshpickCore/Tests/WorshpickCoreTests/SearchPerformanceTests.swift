import Foundation
import Testing
@testable import WorshpickCore

@Suite struct SearchPerformanceTests {
    @Test func searchesFiveThousandSongsUnderFiftyMilliseconds() throws {
        let catalog = try TestCatalog()
        let vocabulary = [
            "gracia", "amor", "cruz", "fuego", "luz", "paz", "gozo", "santo", "rey", "vida", "camino", "verdad",
            "esperanza", "fe", "gloria", "poder", "nombre", "cielo", "tierra", "corazón", "alma", "mano", "río", "roca",
        ]
        var generator = SystemRandomNumberGenerator()
        func randomWords(_ count: Int) -> String {
            (0..<count).map { _ in vocabulary.randomElement(using: &generator)! }.joined(separator: " ")
        }
        let invitations = DefaultVocabularies.invitations
        for index in 0..<5_000 {
            try catalog.addReadySong(AnalyzedSong(
                title: "\(randomWords(3)) \(index)", artist: randomWords(2), language: .es,
                lyrics: (0..<8).map { _ in randomWords(6) }.joined(separator: "\n"), summary: randomWords(12),
                keywords: (0..<10).map { _ in randomWords(1) }, invitations: [invitations.randomElement()!],
                themes: [randomWords(1), randomWords(1)], moments: [DefaultVocabularies.moments.randomElement()!],
                energy: Energy.allCases.randomElement()!, passages: []
            ))
        }

        let filters = SearchFilters(invitations: ["Esperanza", "Confianza"], energies: [.low, .medium])
        var durations: [Duration] = []
        let clock = ContinuousClock()
        for _ in 0..<20 {
            durations.append(try clock.measure { _ = try catalog.searchService.search("gracia cruz fue", filters: filters) })
        }
        let median = durations.sorted()[durations.count / 2]
        print("Search median over 5000 songs: \(median)")
        #expect(median < .milliseconds(50), "median \(median)")
    }
}
