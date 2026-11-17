import Foundation
import OSLog

public struct SongAnalysisContext: Sendable {
    public var originalFileName: String
    public var ocrText: String
    public var invitationVocabulary: [String]
    public var momentVocabulary: [String]
    public var existingThemes: [String]

    public init(originalFileName: String, ocrText: String, invitationVocabulary: [String], momentVocabulary: [String], existingThemes: [String]) {
        self.originalFileName = originalFileName
        self.ocrText = ocrText
        self.invitationVocabulary = invitationVocabulary
        self.momentVocabulary = momentVocabulary
        self.existingThemes = existingThemes
    }
}

public protocol SongAnalyzing: Sendable {
    func analyze(_ context: SongAnalysisContext, model: String) async throws -> AnalyzedSong
}

public struct SongAnalyzer: SongAnalyzing {
    private static let logger = Logger(subsystem: "com.dfeliz.worshpick", category: "SongAnalyzer")
    private static let attemptCount = 2

    private let claudeRunner: any ClaudeRunning

    public init(claudeRunner: any ClaudeRunning) {
        self.claudeRunner = claudeRunner
    }

    public func analyze(_ context: SongAnalysisContext, model: String) async throws -> AnalyzedSong {
        let request = ClaudeRequest(
            prompt: ClaudePrompts.songAnalysis(
                originalFileName: context.originalFileName, ocrText: context.ocrText,
                invitations: context.invitationVocabulary, moments: context.momentVocabulary,
                existingThemes: context.existingThemes
            ),
            jsonSchema: ClaudeSchemas.songAnalysisSchema(invitations: context.invitationVocabulary, moments: context.momentVocabulary),
            model: model
        )

        var lastProblem = ""
        for _ in 1...Self.attemptCount {
            let output = try await claudeRunner.run(request)
            do {
                let response = try JSONDecoder().decode(SongAnalysisResponse.self, from: output)
                try response.validate(invitationVocabulary: context.invitationVocabulary, momentVocabulary: context.momentVocabulary)
                let droppedBooks = response.passages.map(\.book).filter { BibleBooks.book(named: $0) == nil }
                if !droppedBooks.isEmpty {
                    Self.logger.info("Dropped unknown Bible books: \(droppedBooks.joined(separator: ", "), privacy: .public)")
                }
                return response.analyzedSong
            } catch {
                lastProblem = String(describing: error)
            }
        }
        throw ClaudeError.invalidOutput(details: lastProblem)
    }
}
