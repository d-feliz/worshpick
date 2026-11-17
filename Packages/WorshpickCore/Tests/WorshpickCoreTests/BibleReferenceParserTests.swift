import Testing
@testable import WorshpickCore

@Suite struct BibleReferenceParserTests {
    private func reference(_ bookId: Int, _ start: Int, _ end: Int) -> BibleReference {
        BibleReference(bookId: bookId, startPosition: start, endPosition: end)
    }

    @Test(arguments: [
        ("Sal 23", 19, 23001, 23999),
        ("salmo 23:1-3", 19, 23001, 23003),
        ("Isaías 40:31", 23, 40031, 40031),
        ("isaias 40.31", 23, 40031, 40031),
        ("Rom 8:38-9:2", 45, 8038, 9002),
        ("1 Co 13", 46, 13001, 13999),
        ("1Co 13", 46, 13001, 13999),
        ("1 Corinthians 13", 46, 13001, 13999),
        ("Juan 99", 43, 99001, 99999),
        ("Romanos 8-9", 45, 8001, 9999),
        ("Cantar de los Cantares 2", 22, 2001, 2999),
    ])
    func parsesSingleReference(text: String, bookId: Int, start: Int, end: Int) {
        let parsed = BibleReferenceParser.parse(text)
        #expect(parsed.references == [reference(bookId, start, end)])
        #expect(parsed.remainingText == "")
    }

    @Test func keepsTextAroundReference() {
        let parsed = BibleReferenceParser.parse("Romans 8 gracia")
        #expect(parsed.references == [reference(45, 8001, 8999)])
        #expect(parsed.remainingText == "gracia")
    }

    @Test func bookWithoutChapterIsText() {
        let parsed = BibleReferenceParser.parse("salmo")
        #expect(parsed.references.isEmpty)
        #expect(parsed.remainingText == "salmo")
    }

    @Test func plainWordsAreNotReferences() {
        let parsed = BibleReferenceParser.parse("amor de Dios")
        #expect(parsed.references.isEmpty)
        #expect(parsed.remainingText == "amor de Dios")
    }

    @Test func parsesTwoReferences() {
        let parsed = BibleReferenceParser.parse("Isaías 6:3, Apocalipsis 4:8")
        #expect(parsed.references == [reference(23, 6003, 6003), reference(66, 4008, 4008)])
    }

    @Test func rejectsBackwardsRange() {
        #expect(BibleReferenceParser.parse("Romanos 8:30-2").references.isEmpty)
    }

    @Test func overlapIsInclusive() {
        let wholeChapter = reference(45, 8001, 8999)
        #expect(wholeChapter.overlaps(reference(45, 8038, 8039)))
        #expect(!wholeChapter.overlaps(reference(45, 12001, 12002)))
        #expect(!wholeChapter.overlaps(reference(46, 8001, 8999)))
        #expect(reference(45, 8038, 9002).overlaps(reference(45, 9001, 9999)))
    }
}
