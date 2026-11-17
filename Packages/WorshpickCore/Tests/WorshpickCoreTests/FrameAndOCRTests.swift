import CoreGraphics
import Foundation
import Testing
@testable import WorshpickCore

@Suite struct FrameAndOCRTests {
    @Test func sameImageHasZeroDifference() {
        let image = makeSolidImage(gray: 0.3)
        #expect(ScreenFingerprint(of: image).difference(from: ScreenFingerprint(of: image)) == 0)
    }

    @Test func differentScreensHaveLargeDifference() async throws {
        let frames = try await FrameSampler().sampleFrames(from: Fixtures.url("videos/cancion-es.mp4"))
        try #require(frames.count >= 2)
        let difference = ScreenFingerprint(of: frames[0].image).difference(from: ScreenFingerprint(of: frames[1].image))
        #expect(difference > FrameSampler.maximumDifferenceForSameScreen)
    }

    @Test func keepsOneFramePerScreen() async throws {
        let frames = try await FrameSampler().sampleFrames(from: Fixtures.url("videos/cancion-es.mp4"))
        #expect((3...5).contains(frames.count), "got \(frames.count)")
        #expect(frames.map(\.timestamp) == frames.map(\.timestamp).sorted())
    }

    @Test func respectsMaximumFrameCount() async throws {
        let frames = try await FrameSampler(maximumFrameCount: 2).sampleFrames(from: Fixtures.url("videos/cancion-es.mp4"))
        #expect(frames.count == 2)
    }

    @Test func plainVideoCollapsesToOneFrame() async throws {
        #expect(try await FrameSampler().sampleFrames(from: Fixtures.url("videos/sin-texto.mp4")).count == 1)
    }

    @Test func unreadableVideoThrows() async throws {
        await #expect(throws: FrameSamplerError.unreadableVideo) {
            try await FrameSampler().sampleFrames(from: Fixtures.url("catalog-sample.json"))
        }
    }

    @Test func visionReadsSpanishLyrics() async throws {
        let frames = try await FrameSampler().sampleFrames(from: Fixtures.url("videos/cancion-es.mp4"))
        let blocks = try await VisionOCR().recognizeText(in: frames)
        let recognizedWords = Set(OCRTextBlocks.plainText(of: blocks).wordsForMatching)
        let expectedWords = "Nada Nos Separa Coro Esperanza Ni lo alto ni lo profundo nada me apartará Tu amor me sostiene en la tormenta".wordsForMatching
        let foundShare = Double(expectedWords.filter(recognizedWords.contains).count) / Double(expectedWords.count)
        #expect(foundShare >= 0.9, "found \(foundShare): \(blocks.map(\.text))")
        #expect(OCRTextBlocks.averageConfidence(of: blocks) >= Song.needsReviewConfidenceThreshold)
        #expect(blocks.first?.text.contains("\n") == true)
    }

    @Test func visionReadsEnglishLyrics() async throws {
        let frames = try await FrameSampler().sampleFrames(from: Fixtures.url("videos/song-en.mp4"))
        let text = OCRTextBlocks.plainText(of: try await VisionOCR().recognizeText(in: frames)).normalizedForMatching
        #expect(text.contains("grace upon grace"))
        #expect(text.contains("dwelt among us"))
    }

    @Test func videoWithoutTextHasNoBlocks() async throws {
        let frames = try await FrameSampler().sampleFrames(from: Fixtures.url("videos/sin-texto.mp4"))
        #expect(try await VisionOCR().recognizeText(in: frames).isEmpty)
    }

    @Test func mergesConsecutiveDuplicateBlocks() {
        let blocks = [
            OCRTextBlock(timestamp: 0, text: "Santo, santo", confidence: 0.9),
            OCRTextBlock(timestamp: 1, text: "santo santo", confidence: 0.8),
            OCRTextBlock(timestamp: 2, text: "Digno", confidence: 0.7),
            OCRTextBlock(timestamp: 3, text: "Santo, santo", confidence: 0.9),
        ]
        #expect(OCRTextBlocks.mergeConsecutiveDuplicates(blocks).map(\.timestamp) == [0, 2, 3])
        #expect(OCRTextBlocks.averageConfidence(of: []) == 0)
    }

    @Test func evenSamplingKeepsEndsAndOrder() {
        #expect(Array(0..<10).evenlySpaced(count: 4) == [0, 3, 6, 9])
        #expect(Array(0..<3).evenlySpaced(count: 5) == [0, 1, 2])
        #expect(Array(0..<3).evenlySpaced(count: 0) == [])
    }
}
