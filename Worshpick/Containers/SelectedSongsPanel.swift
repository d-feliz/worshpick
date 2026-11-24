import SwiftUI
import WorshpickCore

struct SelectedSongsPanel: View {
    @Environment(AppModel.self) private var model
    let songIds: [UUID]
    let onDeleteRequest: () -> Void
    let onClearSelection: () -> Void

    private var songs: [Song] { songIds.compactMap(model.song(id:)) }

    var body: some View {
        let failedCount = songs.filter { $0.status == .failed }.count
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(songIds.count) canciones seleccionadas").font(.title2.bold())
                if failedCount > 0 {
                    Label("\(failedCount) con error", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Button { model.addToCurrentSetlist(songIds: songIds) } label: {
                    Label("Añadir al setlist", systemImage: "plus.circle")
                }
                Button { Task { await model.reanalyze(songIds: songIds) } } label: {
                    Label("Reanalizar", systemImage: "arrow.clockwise")
                }
                .help("Claude vuelve a etiquetar la letra ya leída. Si no hay letra, vuelve a leer el video.")
                Button { Task { await model.reprocessWithClaudeOCR(songIds: songIds) } } label: {
                    Label("Reprocesar con Claude OCR", systemImage: "text.viewfinder")
                }
                .help("Claude lee los fotogramas del video. Úsalo cuando no se encontró texto.")
                Divider()
                Button(role: .destructive, action: onDeleteRequest) {
                    Label("Eliminar de la biblioteca…", systemImage: "trash")
                }
                Button("Deseleccionar", action: onClearSelection)
            }
            .buttonStyle(.borderless)
            Text("Shift + clic o Shift + flechas para elegir un rango. ⌘ + clic para añadir o quitar una canción.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}
