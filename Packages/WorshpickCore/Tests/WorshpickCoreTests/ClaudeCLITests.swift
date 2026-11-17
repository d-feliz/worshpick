import Foundation
import Testing
@testable import WorshpickCore

@Suite struct ClaudeCLITests {
    @Test func readsStructuredOutput() throws {
        let data = try ClaudeResultEnvelope.structuredOutput(from: Fixtures.data("claude-cli/success-structured.handmade.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["word"] as? String == "gracia")
    }

    @Test func authenticationErrorMeansNotLoggedIn() throws {
        #expect {
            try ClaudeResultEnvelope.structuredOutput(from: Fixtures.data("claude-cli/auth-error.json"))
        } throws: { error in
            guard case ClaudeError.notLoggedIn = error else { return false }
            return (error as? ClaudeError)?.pausesQueue == true
        }
    }

    @Test func usageLimitError() throws {
        #expect {
            try ClaudeResultEnvelope.structuredOutput(from: Fixtures.data("claude-cli/usage-limit.handmade.json"))
        } throws: { error in
            if case ClaudeError.usageLimitReached = error { return true }
            return false
        }
    }

    @Test func nonJSONOutputIsInvalid() {
        #expect {
            try ClaudeResultEnvelope.structuredOutput(from: Data("hola".utf8))
        } throws: { error in
            if case ClaudeError.invalidOutput = error { return true }
            return false
        }
    }

    @Test func otherErrorsDoNotPauseQueue() {
        #expect(ClaudeResultEnvelope.error(forResultText: "boom") == .failed(message: "boom"))
        #expect(!ClaudeError.timedOut.pausesQueue)
    }

    @Test func buildsArgumentsWithoutTools() {
        let arguments = ProcessClaudeRunner.arguments(for: ClaudeRequest(prompt: "p", jsonSchema: "{}", model: "sonnet"))
        #expect(arguments == ["-p", "--output-format", "json", "--no-session-persistence", "--model", "sonnet", "--json-schema", "{}", "--tools", ""])
    }

    @Test func buildsArgumentsWithReadToolAndFolder() {
        let folder = URL(fileURLWithPath: "/tmp/frames")
        let arguments = ProcessClaudeRunner.arguments(for: ClaudeRequest(
            prompt: "p", jsonSchema: "{}", model: "haiku", allowedTools: ["Read"], readableDirectories: [folder]
        ))
        #expect(arguments.suffix(6) == ["--tools", "Read", "--allowedTools", "Read", "--add-dir", "/tmp/frames"])
    }

    @Test func locatorPrefersConfiguredPathThenKnownFolders() {
        let home = URL(fileURLWithPath: "/Users/test")
        let configured = ClaudeBinaryLocator(
            configuredPath: "/custom/claude", homeDirectory: home,
            isExecutableFile: { ["/custom/claude", "/opt/homebrew/bin/claude"].contains($0) }, loginShellLookup: { nil }
        )
        #expect(configured.locate()?.path == "/custom/claude")

        let homebrewOnly = ClaudeBinaryLocator(
            configuredPath: nil, homeDirectory: home,
            isExecutableFile: { $0 == "/opt/homebrew/bin/claude" }, loginShellLookup: { nil }
        )
        #expect(homebrewOnly.locate()?.path == "/opt/homebrew/bin/claude")

        let shellOnly = ClaudeBinaryLocator(
            configuredPath: nil, homeDirectory: home,
            isExecutableFile: { $0 == "/elsewhere/claude" }, loginShellLookup: { "/elsewhere/claude" }
        )
        #expect(shellOnly.locate()?.path == "/elsewhere/claude")

        let missing = ClaudeBinaryLocator(configuredPath: nil, homeDirectory: home, isExecutableFile: { _ in false }, loginShellLookup: { nil })
        #expect(missing.locate() == nil)
    }

    @Test func missingBinaryThrowsNotInstalled() async {
        let locator = ClaudeBinaryLocator(
            configuredPath: nil, homeDirectory: URL(fileURLWithPath: "/nowhere"), isExecutableFile: { _ in false }, loginShellLookup: { nil }
        )
        await #expect(throws: ClaudeError.notInstalled) {
            try await ProcessClaudeRunner(binaryLocator: locator).run(ClaudeRequest(prompt: "p", jsonSchema: "{}", model: "m"))
        }
    }

    @Test func runsAScriptThatBehavesLikeTheCLI() async throws {
        let folder = try makeTemporaryFolder()
        let scriptURL = folder.appending(path: "claude")
        let envelopePath = Fixtures.url("claude-cli/success-structured.handmade.json").path
        try """
            #!/bin/sh
            cat > /dev/null
            cat "\(envelopePath)"
            """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let runner = ProcessClaudeRunner(binaryLocator: ClaudeBinaryLocator(configuredPath: scriptURL.path))
        let data = try await runner.run(ClaudeRequest(prompt: String(repeating: "letra ", count: 50_000), jsonSchema: "{}", model: "m"))
        #expect(String(decoding: data, as: UTF8.self).contains("gracia"))
    }

    @Test func timeoutStopsTheProcess() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ClaudeError.timedOut) {
            try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], standardInput: Data(),
                workingDirectory: FileManager.default.temporaryDirectory, timeout: .milliseconds(300)
            )
        }
        #expect(clock.now - start < .seconds(5))
    }
}
