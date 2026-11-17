import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist so search rows can be dropped on the AppKit setlist table.
    static let worshpickSong = UTType(exportedAs: "com.dfeliz.worshpick.song")
}

struct SongDragItem: Codable, Transferable {
    var songIds: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .worshpickSong)
    }
}
