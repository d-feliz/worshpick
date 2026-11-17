import Foundation

/// Thread-safe so background work (the ingest queue) can read the current settings.
public final class SettingsStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var settings: AppSettings

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let savedData = try? Data(contentsOf: fileURL)
        settings = savedData.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    public static var defaultFileURL: URL {
        LibraryService.defaultLibraryFolder.appending(path: "settings.json")
    }

    public var current: AppSettings {
        lock.withLock { settings }
    }

    public func update(_ change: (inout AppSettings) -> Void) throws {
        let updatedSettings: AppSettings = lock.withLock {
            change(&settings)
            return settings
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updatedSettings).write(to: fileURL, options: .atomic)
    }
}
