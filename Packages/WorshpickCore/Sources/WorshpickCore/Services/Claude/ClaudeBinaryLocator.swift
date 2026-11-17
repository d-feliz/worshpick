import Foundation

public struct ClaudeBinaryLocator: Sendable {
    public var configuredPath: String?
    var homeDirectory: URL
    var isExecutableFile: @Sendable (String) -> Bool
    var loginShellLookup: @Sendable () -> String?

    public init(configuredPath: String? = nil) {
        self.init(
            configuredPath: configuredPath,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            isExecutableFile: { FileManager.default.isExecutableFile(atPath: $0) },
            loginShellLookup: Self.lookUpWithLoginShell
        )
    }

    init(
        configuredPath: String?, homeDirectory: URL,
        isExecutableFile: @escaping @Sendable (String) -> Bool, loginShellLookup: @escaping @Sendable () -> String?
    ) {
        self.configuredPath = configuredPath
        self.homeDirectory = homeDirectory
        self.isExecutableFile = isExecutableFile
        self.loginShellLookup = loginShellLookup
    }

    /// An app opened from Finder does not inherit the Terminal PATH, so the usual install folders are checked by hand.
    public func locate() -> URL? {
        var candidates: [String] = []
        if let configuredPath, !configuredPath.isEmpty { candidates.append(configuredPath) }
        candidates += [
            homeDirectory.appending(path: ".local/bin/claude").path,
            homeDirectory.appending(path: ".claude/local/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let executablePath = candidates.first(where: isExecutableFile) {
            return URL(fileURLWithPath: executablePath)
        }
        if let shellPath = loginShellLookup(), isExecutableFile(shellPath) {
            return URL(fileURLWithPath: shellPath)
        }
        return nil
    }

    private static func lookUpWithLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }
}
