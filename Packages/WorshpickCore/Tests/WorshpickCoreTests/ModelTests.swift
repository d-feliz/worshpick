import Foundation
import Testing
@testable import WorshpickCore

@Suite struct ModelTests {
    @Test func songRoundTripsThroughCodable() throws {
        var song = Song.pending(videoRelativePath: "Videos/a/b.mp4", originalFileName: "b.mp4", fileHash: "hash", duration: 12)
        song.invitations = ["Alegría"]
        song.manuallyEditedFields = [.title, .themes]
        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
        #expect(decoded == song)
    }

    @Test func pendingSongTitleComesFromFileName() {
        let song = Song.pending(videoRelativePath: "x", originalFileName: "Nada Nos Separa.mp4", fileHash: "h", duration: 1)
        #expect(song.title == "Nada Nos Separa")
        #expect(song.status == .pending)
    }

    @Test func needsReviewBelowConfidenceThreshold() {
        var song = Song.pending(videoRelativePath: "x", originalFileName: "a.mp4", fileHash: "h", duration: 1)
        #expect(!song.needsReview)
        song.ocrConfidence = 0.59
        #expect(song.needsReview)
        song.ocrConfidence = 0.6
        #expect(!song.needsReview)
    }

    @Test func setlistRoundTripsThroughCodable() throws {
        let setlist = Setlist(serviceDate: makeDate("2026-11-22"), serviceDescription: "Romanos 8")
        let decoded = try JSONDecoder().decode(Setlist.self, from: JSONEncoder().encode(setlist))
        #expect(decoded == setlist)
    }

    @Test(arguments: [
        ("Romanos 8", 8001, 8999),
        ("Romanos 8:28", 8028, 8028),
        ("Romanos 8:28-39", 8028, 8039),
        ("Romanos 8:38-9:2", 8038, 9002),
    ])
    func referencePositions(text: String, start: Int, end: Int) throws {
        let reference = try #require(BibleReferenceParser.parseSingleReference(text))
        #expect(reference.startPosition == start)
        #expect(reference.endPosition == end)
    }

    @Test func referenceDisplayText() throws {
        #expect(try #require(BibleReferenceParser.parseSingleReference("Rom 8")).displayText == "Romanos 8")
        #expect(try #require(BibleReferenceParser.parseSingleReference("Rom 8:38-39")).displayText == "Romanos 8:38-39")
        #expect(try #require(BibleReferenceParser.parseSingleReference("Sal 23:1")).displayText == "Salmos 23:1")
    }
}
