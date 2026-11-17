import Foundation

/// Reads the CLI path from Settings on every call, so changing it takes effect without restarting the app.
public struct SettingsAwareClaudeRunner: ClaudeRunning {
    private let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    public func run(_ request: ClaudeRequest) async throws -> Data {
        let locator = ClaudeBinaryLocator(configuredPath: settingsStore.current.claudeBinaryPath)
        return try await ProcessClaudeRunner(binaryLocator: locator).run(request)
    }
}

public enum ClaudeConnectionTest {
    public static func run(using claudeRunner: any ClaudeRunning, model: String) async throws {
        let output = try await claudeRunner.run(ClaudeRequest(
            prompt: ClaudePrompts.connectionTest, jsonSchema: ClaudeSchemas.connectionTestSchema, model: model, timeout: .seconds(60)
        ))
        let isConfirmed = (try? JSONSerialization.jsonObject(with: output) as? [String: Any])?["ok"] as? Bool ?? false
        guard isConfirmed else { throw ClaudeError.invalidOutput(details: String(decoding: output, as: UTF8.self)) }
    }
}
