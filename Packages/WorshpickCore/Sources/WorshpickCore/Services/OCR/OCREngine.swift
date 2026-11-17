import Foundation

public struct OCRTextBlock: Codable, Sendable, Equatable {
    public var timestamp: TimeInterval
    public var text: String
    public var confidence: Double

    public init(timestamp: TimeInterval, text: String, confidence: Double) {
        self.timestamp = timestamp
        self.text = text
        self.confidence = confidence
    }
}

public protocol OCREngine: Sendable {
    func recognizeText(in frames: [SampledFrame]) async throws -> [OCRTextBlock]
}

public enum OCRTextBlocks {
    public static func mergeConsecutiveDuplicates(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        var mergedBlocks: [OCRTextBlock] = []
        for block in blocks {
            let isSameTextAsPrevious = mergedBlocks.last.map { comparableText($0.text) == comparableText(block.text) } ?? false
            if isSameTextAsPrevious { continue }
            mergedBlocks.append(block)
        }
        return mergedBlocks
    }

    public static func averageConfidence(of blocks: [OCRTextBlock]) -> Double {
        guard !blocks.isEmpty else { return 0 }
        return blocks.map(\.confidence).reduce(0, +) / Double(blocks.count)
    }

    /// One block per screen, separated by a blank line. This is the stored `Song.ocrText`.
    public static func plainText(of blocks: [OCRTextBlock]) -> String {
        blocks.map(\.text).joined(separator: "\n\n")
    }

    private static func comparableText(_ text: String) -> String {
        text.wordsForMatching.joined(separator: " ")
    }
}
