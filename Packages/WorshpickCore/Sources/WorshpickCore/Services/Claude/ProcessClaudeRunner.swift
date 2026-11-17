import Foundation

public struct ProcessClaudeRunner: ClaudeRunning {
    private let binaryLocator: ClaudeBinaryLocator

    public init(binaryLocator: ClaudeBinaryLocator = ClaudeBinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    public func run(_ request: ClaudeRequest) async throws -> Data {
        guard let binaryURL = binaryLocator.locate() else { throw ClaudeError.notInstalled }
        let processResult = try await ProcessRunner.run(
            executableURL: binaryURL,
            arguments: Self.arguments(for: request),
            standardInput: Data(request.prompt.utf8),
            workingDirectory: request.readableDirectories.first ?? FileManager.default.temporaryDirectory,
            extraPathFolders: [binaryURL.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"],
            timeout: request.timeout
        )
        if processResult.standardOutput.isEmpty {
            let errorText = String(decoding: processResult.standardError, as: UTF8.self)
            throw ClaudeResultEnvelope.error(forResultText: errorText)
        }
        return try ClaudeResultEnvelope.structuredOutput(from: processResult.standardOutput)
    }

    /// The prompt goes through stdin, so long OCR text never hits the argument length limit.
    static func arguments(for request: ClaudeRequest) -> [String] {
        var arguments = [
            "-p",
            "--output-format", "json",
            "--no-session-persistence",
            "--model", request.model,
            "--json-schema", request.jsonSchema,
            "--tools", request.allowedTools.joined(separator: ","),
        ]
        if !request.allowedTools.isEmpty {
            arguments += ["--allowedTools", request.allowedTools.joined(separator: ",")]
        }
        for directory in request.readableDirectories {
            arguments += ["--add-dir", directory.path]
        }
        return arguments
    }
}

struct ProcessResult: Sendable {
    var exitCode: Int32
    var standardOutput: Data
    var standardError: Data
}

enum ProcessRunner {
    static func run(
        executableURL: URL, arguments: [String], standardInput: Data, workingDirectory: URL,
        extraPathFolders: [String] = [], timeout: Duration
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (extraPathFolders + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let collectedOutput = LockedData()
        let collectedError = LockedData()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in collectedOutput.append(handle.availableData) }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in collectedError.append(handle.availableData) }

        let timeoutFlag = LockedFlag()
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finishedProcess in
                    continuation.resume(returning: finishedProcess.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: ClaudeError.failed(message: error.localizedDescription))
                    return
                }
                inputPipe.fileHandleForWriting.writeabilityHandler = nil
                DispatchQueue.global().async {
                    try? inputPipe.fileHandleForWriting.write(contentsOf: standardInput)
                    try? inputPipe.fileHandleForWriting.close()
                }
                Task {
                    try? await Task.sleep(for: timeout)
                    if process.isRunning {
                        timeoutFlag.set()
                        process.terminate()
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        collectedOutput.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        collectedError.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        if timeoutFlag.isSet { throw ClaudeError.timedOut }
        return ProcessResult(exitCode: exitCode, standardOutput: collectedOutput.value, standardError: collectedError.value)
    }
}

final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.withLock { data.append(newData) }
    }

    var value: Data { lock.withLock { data } }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() { lock.withLock { flag = true } }
    var isSet: Bool { lock.withLock { flag } }
}
