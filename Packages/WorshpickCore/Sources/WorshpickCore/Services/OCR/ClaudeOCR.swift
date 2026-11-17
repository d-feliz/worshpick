import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ClaudeOCR: OCREngine {
    public static let maximumFrameCount = 40
    /// Claude does not report a confidence; its reading is trusted like a high-confidence OCR.
    static let assumedConfidence = 1.0

    private let claudeRunner: any ClaudeRunning
    private let modelProvider: @Sendable () -> String

    public init(claudeRunner: any ClaudeRunning, modelProvider: @escaping @Sendable () -> String) {
        self.claudeRunner = claudeRunner
        self.modelProvider = modelProvider
    }

    public func recognizeText(in frames: [SampledFrame]) async throws -> [OCRTextBlock] {
        let selectedFrames = frames.evenlySpaced(count: Self.maximumFrameCount)
        guard !selectedFrames.isEmpty else { return [] }

        let framesFolder = FileManager.default.temporaryDirectory.appending(path: "worshpick-frames-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: framesFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: framesFolder) }

        var frameFileNames: [String] = []
        for (index, frame) in selectedFrames.enumerated() {
            let fileName = String(format: "frame-%03d.jpg", index)
            try Self.writeJPEG(frame.image, to: framesFolder.appending(path: fileName))
            frameFileNames.append(fileName)
        }

        let output = try await claudeRunner.run(ClaudeRequest(
            prompt: ClaudePrompts.frameOCR(frameFileNames: frameFileNames),
            jsonSchema: ClaudeSchemas.ocrSchema,
            model: modelProvider(),
            allowedTools: ["Read"],
            readableDirectories: [framesFolder]
        ))
        let response: OCRResponse
        do {
            response = try JSONDecoder().decode(OCRResponse.self, from: output)
        } catch {
            throw ClaudeError.invalidOutput(details: String(describing: error))
        }

        let blocks = response.blocks
            .filter { selectedFrames.indices.contains($0.frameIndex) && $0.text.containsLetterOrDigit }
            .sorted { $0.frameIndex < $1.frameIndex }
            .map { OCRTextBlock(timestamp: selectedFrames[$0.frameIndex].timestamp, text: $0.text, confidence: Self.assumedConfidence) }
        return OCRTextBlocks.mergeConsecutiveDuplicates(blocks)
    }

    private static func writeJPEG(_ image: CGImage, to fileURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
