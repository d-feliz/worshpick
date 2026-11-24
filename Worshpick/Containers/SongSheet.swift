import SwiftUI
import WorshpickCore

struct SongSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let songId: UUID

    private var song: Song? {
        _ = model.catalogRevision
        return model.song(id: songId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let song {
                    SongDetailPanel(song: song)
                } else {
                    ContentUnavailableView("La canción ya no está en la biblioteca", systemImage: "music.note")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 560, idealHeight: 720)
    }
}
