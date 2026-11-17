import Foundation

/// Reads the JSON that `claude -p --output-format json` prints.
public enum ClaudeResultEnvelope {
    public static func structuredOutput(from cliOutput: Data) throws -> Data {
        guard let envelope = try? JSONSerialization.jsonObject(with: cliOutput) as? [String: Any] else {
            let preview = String(decoding: cliOutput.prefix(300), as: UTF8.self)
            throw ClaudeError.invalidOutput(details: "La salida del CLI no es JSON: \(preview)")
        }

        let resultText = envelope["result"] as? String ?? ""
        let isError = envelope["is_error"] as? Bool ?? false
        if isError {
            throw error(forResultText: resultText)
        }

        if let structuredOutput = envelope["structured_output"], !(structuredOutput is NSNull) {
            return try JSONSerialization.data(withJSONObject: structuredOutput)
        }
        if let resultData = resultText.data(using: .utf8),
           let resultObject = try? JSONSerialization.jsonObject(with: resultData),
           resultObject is [String: Any] {
            return resultData
        }
        throw ClaudeError.invalidOutput(details: "Falta structured_output")
    }

    static func error(forResultText resultText: String) -> ClaudeError {
        let normalizedText = resultText.lowercased()
        let isAuthenticationProblem = ["authenticate", "login", "log in", "oauth", "api key"].contains { normalizedText.contains($0) }
        if isAuthenticationProblem { return .notLoggedIn(message: resultText) }
        let isUsageLimit = ["usage limit", "rate limit", "limit reached", "quota"].contains { normalizedText.contains($0) }
        if isUsageLimit { return .usageLimitReached(message: resultText) }
        return .failed(message: resultText.isEmpty ? "Error desconocido" : resultText)
    }
}
