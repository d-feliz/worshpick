import Foundation
import Vision

public struct VisionOCR: OCREngine {
    public init() {}

    public func recognizeText(in frames: [SampledFrame]) async throws -> [OCRTextBlock] {
        var blocks: [OCRTextBlock] = []
        for frame in frames {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [Locale.Language(identifier: "es-ES"), Locale.Language(identifier: "en-US")]
            request.usesLanguageCorrection = true
            let observations = try await request.perform(on: frame.image)

            let linesTopToBottom = observations
                .compactMap { observation -> (text: String, confidence: Double, top: CGFloat, left: CGFloat)? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox.cgRect
                    return (candidate.string, Double(candidate.confidence), box.maxY, box.minX)
                }
                .sorted { $0.top == $1.top ? $0.left < $1.left : $0.top > $1.top }
            guard !linesTopToBottom.isEmpty else { continue }

            let averageLineConfidence = linesTopToBottom.map(\.confidence).reduce(0, +) / Double(linesTopToBottom.count)
            blocks.append(OCRTextBlock(
                timestamp: frame.timestamp,
                text: linesTopToBottom.map(\.text).joined(separator: "\n"),
                confidence: averageLineConfidence
            ))
        }
        return OCRTextBlocks.mergeConsecutiveDuplicates(blocks)
    }
}
