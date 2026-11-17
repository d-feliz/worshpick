import Foundation
import Testing
@testable import WorshpickCore

@Suite struct ClaudeOCRTests {
    @Test func writesFramesForTheCallAndCleansUp() async throws {
        let runner = FakeClaudeRunner([.json(#"{"blocks": [{"frameIndex": 1, "text": "Santo"}, {"frameIndex": 0, "text": "Digno"}, {"frameIndex": 9, "text": "fuera"}]}"#)])
        let filesSeenDuringCall = LockedData()
        runner.onRun = { request in
            let folder = request.readableDirectories[0]
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            filesSeenDuringCall.append(Data(names.sorted().joined(separator: ",").utf8))
        }
        let frames = [0.0, 1.5, 3.0].map { SampledFrame(timestamp: $0, image: makeSolidImage(gray: $0 / 10)) }
        let blocks = try await ClaudeOCR(claudeRunner: runner, modelProvider: { "sonnet" }).recognizeText(in: frames)

        #expect(String(decoding: filesSeenDuringCall.value, as: UTF8.self) == "frame-000.jpg,frame-001.jpg,frame-002.jpg")
        #expect(blocks.map(\.text) == ["Digno", "Santo"])
        #expect(blocks.map(\.timestamp) == [0.0, 1.5])
        let request = try #require(runner.requests.first)
        #expect(request.allowedTools == ["Read"])
        #expect(!FileManager.default.fileExists(atPath: request.readableDirectories[0].path))
    }

    @Test func cleansUpWhenClaudeFails() async throws {
        let runner = FakeClaudeRunner([.error(.timedOut)])
        let frames = [SampledFrame(timestamp: 0, image: makeSolidImage(gray: 0.2))]
        await #expect(throws: ClaudeError.timedOut) {
            try await ClaudeOCR(claudeRunner: runner, modelProvider: { "sonnet" }).recognizeText(in: frames)
        }
        #expect(!FileManager.default.fileExists(atPath: try #require(runner.requests.first).readableDirectories[0].path))
    }

    @Test func sendsAtMostFortyFramesSpreadEvenly() async throws {
        let runner = FakeClaudeRunner([.json(#"{"blocks": []}"#)])
        let frames = (0..<100).map { SampledFrame(timestamp: Double($0), image: makeSolidImage(gray: 0.5)) }
        _ = try await ClaudeOCR(claudeRunner: runner, modelProvider: { "sonnet" }).recognizeText(in: frames)
        let prompt = try #require(runner.requests.first?.prompt)
        #expect(prompt.contains("39: frame-039.jpg"))
        #expect(!prompt.contains("frame-040.jpg"))
    }
}
