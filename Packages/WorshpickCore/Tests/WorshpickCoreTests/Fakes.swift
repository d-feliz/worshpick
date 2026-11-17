import CoreGraphics
import Foundation
@testable import WorshpickCore

final class FakeClaudeRunner: ClaudeRunning, @unchecked Sendable {
    enum Response {
        case json(String)
        case error(ClaudeError)
    }

    private let lock = NSLock()
    private var queuedResponses: [Response]
    private var recordedRequests: [ClaudeRequest] = []
    var onRun: (@Sendable (ClaudeRequest) -> Void)?

    init(_ responses: [Response] = []) {
        queuedResponses = responses
    }

    func enqueue(_ response: Response) {
        lock.withLock { queuedResponses.append(response) }
    }

    var requests: [ClaudeRequest] { lock.withLock { recordedRequests } }

    func run(_ request: ClaudeRequest) async throws -> Data {
        onRun?(request)
        let response: Response? = lock.withLock {
            recordedRequests.append(request)
            return queuedResponses.isEmpty ? nil : queuedResponses.removeFirst()
        }
        switch response {
        case .json(let json): return Data(json.utf8)
        case .error(let error): throw error
        case nil: throw ClaudeError.failed(message: "FakeClaudeRunner has no response left")
        }
    }
}

struct FakeFrameSampler: FrameSampling {
    var frameCount = 2
    var error: Error?

    func sampleFrames(from videoURL: URL, interval: TimeInterval) async throws -> [SampledFrame] {
        if let error { throw error }
        return (0..<frameCount).map { SampledFrame(timestamp: Double($0) * interval, image: makeSolidImage(gray: CGFloat($0) / 10)) }
    }
}

final class FakeOCREngine: OCREngine, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    var blocks: [OCRTextBlock]
    var error: Error?

    init(blocks: [OCRTextBlock] = [OCRTextBlock(timestamp: 0, text: "Ni lo alto\nni lo profundo", confidence: 0.9)], error: Error? = nil) {
        self.blocks = blocks
        self.error = error
    }

    var calls: Int { lock.withLock { callCount } }

    func recognizeText(in frames: [SampledFrame]) async throws -> [OCRTextBlock] {
        lock.withLock { callCount += 1 }
        if let error { throw error }
        return blocks
    }
}

final class FakeSongAnalyzer: SongAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedResults: [Result<AnalyzedSong, Error>]
    private var receivedContexts: [SongAnalysisContext] = []
    var delay: Duration = .zero

    init(_ results: [Result<AnalyzedSong, Error>] = []) {
        queuedResults = results
    }

    func enqueue(_ result: Result<AnalyzedSong, Error>) {
        lock.withLock { queuedResults.append(result) }
    }

    var contexts: [SongAnalysisContext] { lock.withLock { receivedContexts } }

    func analyze(_ context: SongAnalysisContext, model: String) async throws -> AnalyzedSong {
        if delay > .zero { try await Task.sleep(for: delay) }
        let result: Result<AnalyzedSong, Error> = lock.withLock {
            receivedContexts.append(context)
            return queuedResults.isEmpty ? .success(.sample(title: context.originalFileName)) : queuedResults.removeFirst()
        }
        return try result.get()
    }
}

func makeSolidImage(gray: CGFloat, width: Int = 64, height: Int = 36) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func makeTemporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "worshpick-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

enum SampleClaudeResponses {
    static func songAnalysis(
        title: String = "Nada Nos Separa", invitations: [String] = ["Confianza"],
        passages: String = #"[{"book": "Romanos", "chapter": 8, "verseStart": 38, "verseEnd": 39, "chapterEnd": null, "kind": "quote"}]"#
    ) -> String {
        """
        {"title": "\(title)", "artist": "Coro Esperanza", "language": "es",
         "lyrics": "Ni lo alto ni lo profundo\\nnada me apartará", "summary": "Confianza en el amor de Dios.",
         "keywords": ["seguridad","amor eterno","fidelidad","refugio","paz","promesa","victoria","firmeza","esperanza","consuelo"],
         "invitations": \(String(decoding: try! JSONSerialization.data(withJSONObject: invitations), as: UTF8.self)),
         "themes": ["Amor de Dios", "seguridad"], "moments": ["Adoración"], "energy": "medium",
         "passages": \(passages)}
        """
    }
}
