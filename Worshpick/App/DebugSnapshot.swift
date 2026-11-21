#if DEBUG
import AppKit
import WorshpickCore

/// Development aid: renders the app's own window to PNG, which needs no screen-recording permission.
/// Driven by WORSHPICK_SNAPSHOT_FOLDER; the other WORSHPICK_DEMO_* variables set up what to show.
@MainActor
enum DebugSnapshot {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var snapshotFolder: URL? { environment["WORSHPICK_SNAPSHOT_FOLDER"].map { URL(fileURLWithPath: $0) } }
    static var initialSection: SidebarSection? { environment["WORSHPICK_DEMO_SECTION"].flatMap(SidebarSection.init(rawValue:)) }
    static var initialSearchText: String? { environment["WORSHPICK_DEMO_SEARCH"] }
    static var showsSetlistPanelOnly: Bool { environment["WORSHPICK_DEMO_PANEL_ONLY"] == "1" }
    static var selectsFirstResult: Bool { environment["WORSHPICK_DEMO_SELECT_FIRST"] == "1" }
    /// WORSHPICK_DEMO_WINDOW_SIZE=960x600
    static var windowSize: CGSize {
        let dimensions = (environment["WORSHPICK_DEMO_WINDOW_SIZE"] ?? "").split(separator: "x").compactMap { Double($0) }
        guard dimensions.count == 2 else { return CGSize(width: 1500, height: 860) }
        return CGSize(width: dimensions[0], height: dimensions[1])
    }

    static func prepareDemoSetlist(in model: AppModel) {
        guard environment["WORSHPICK_DEMO_SETLIST"] == "1", model.currentSetlist?.items.isEmpty ?? true else { return }
        let titles = ["Fuego Santo", "Nada Nos Separa", "Mi Pastor", "Sacrificio Vivo"]
        let songs = (try? model.catalogStore.allSongs()) ?? []
        let songIds = titles.compactMap { title in songs.first { $0.title == title }?.id }
        model.createSetlist(serviceDescription: "Romanos 8: nada nos separa del amor de Dios")
        model.addToCurrentSetlist(songIds: songIds)
    }

    static func captureWhenReady() async {
        guard let snapshotFolder else { return }
        FileHandle.standardError.write(Data("DebugSnapshot: waiting\n".utf8))
        try? await Task.sleep(for: .seconds(3))
        FileHandle.standardError.write(Data("DebugSnapshot: windows \(NSApp.windows.map { "\($0.title) \($0.frame) visible=\($0.isVisible)" })\n".utf8))
        let visibleWindows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 300 }
        guard let window = visibleWindows.max(by: { $0.frame.width < $1.frame.width }) else {
            FileHandle.standardError.write(Data("DebugSnapshot: no window among \(NSApp.windows.map(\.title))\n".utf8))
            NSApp.terminate(nil)
            return
        }
        if !showsSetlistPanelOnly { window.setFrame(NSRect(origin: CGPoint(x: 40, y: 40), size: windowSize), display: true) }
        try? await Task.sleep(for: .seconds(1.5))
        guard let contentView = window.contentView,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            FileHandle.standardError.write(Data("DebugSnapshot: no window among \(NSApp.windows.map(\.title))\n".utf8))
            NSApp.terminate(nil)
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        let name = environment["WORSHPICK_SNAPSHOT_NAME"] ?? "window"
        try? FileManager.default.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: snapshotFolder.appending(path: "\(name).png"))
        NSApp.terminate(nil)
    }
}
#endif
