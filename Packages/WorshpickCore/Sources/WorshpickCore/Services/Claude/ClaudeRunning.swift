import Foundation

public struct ClaudeRequest: Sendable {
    public static let defaultTimeout: Duration = .seconds(180)

    public var prompt: String
    public var jsonSchema: String
    public var model: String
    public var allowedTools: [String]
    public var readableDirectories: [URL]
    public var timeout: Duration

    public init(
        prompt: String, jsonSchema: String, model: String, allowedTools: [String] = [],
        readableDirectories: [URL] = [], timeout: Duration = defaultTimeout
    ) {
        self.prompt = prompt
        self.jsonSchema = jsonSchema
        self.model = model
        self.allowedTools = allowedTools
        self.readableDirectories = readableDirectories
        self.timeout = timeout
    }
}

public enum ClaudeError: Error, Equatable, LocalizedError {
    case notInstalled
    case notLoggedIn(message: String)
    case usageLimitReached(message: String)
    case timedOut
    case invalidOutput(details: String)
    case failed(message: String)

    /// These errors affect every song, so the ingest queue pauses instead of failing each song.
    public var pausesQueue: Bool {
        switch self {
        case .notInstalled, .notLoggedIn, .usageLimitReached: true
        case .timedOut, .invalidOutput, .failed: false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "No se encontró el CLI de Claude. Instálalo o indica su ruta en Ajustes."
        case .notLoggedIn(let message):
            "El CLI de Claude no tiene sesión. Abre Terminal y ejecuta `claude` para iniciar sesión. (\(message))"
        case .usageLimitReached(let message):
            "Se alcanzó el límite de uso de Claude. (\(message))"
        case .timedOut:
            "Claude tardó demasiado en responder."
        case .invalidOutput(let details):
            "Claude devolvió una respuesta no válida: \(details)"
        case .failed(let message):
            "Claude falló: \(message)"
        }
    }
}

public protocol ClaudeRunning: Sendable {
    /// Returns the structured JSON object that matches `request.jsonSchema`.
    func run(_ request: ClaudeRequest) async throws -> Data
}
