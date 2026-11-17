import Testing
@testable import WorshpickCore

@Suite struct BibleBooksTests {
    @Test func thereAreSixtySixBooksWithSequentialIds() {
        #expect(BibleBooks.all.count == 66)
        #expect(BibleBooks.all.map(\.id) == Array(1...66))
    }

    @Test func noLookupKeyPointsToTwoBooks() {
        var bookIdByKey: [String: Int] = [:]
        var collisions: [String] = []
        for book in BibleBooks.all {
            for name in Set(book.allNames.map(BibleBooks.lookupKey(for:))) {
                if let existingBookId = bookIdByKey[name], existingBookId != book.id {
                    collisions.append("\(name): \(existingBookId) vs \(book.id)")
                }
                bookIdByKey[name] = book.id
            }
        }
        #expect(collisions.isEmpty, "\(collisions)")
    }

    @Test(arguments: [
        ("Génesis", 1), ("gen", 1), ("Salmo", 19), ("Ps", 19), ("1 Co", 46), ("1Co", 46), ("1 Cor.", 46),
        ("1 Corinthians", 46), ("Cantar de los Cantares", 22), ("Song of Songs", 22), ("Apocalipsis", 66),
        ("Rev", 66), ("Hechos", 44), ("3 Juan", 64), ("Santiago", 59), ("James", 59),
    ])
    func findsBookByName(name: String, expectedId: Int) {
        #expect(BibleBooks.book(named: name)?.id == expectedId)
    }
}
