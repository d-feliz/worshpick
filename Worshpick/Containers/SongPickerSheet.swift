import SwiftUI
import WorshpickCore

struct SongPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (UUID) -> Void

    @State private var searchText = ""
    @State private var results: [SearchResult] = []

    var body: some View {
        VStack(spacing: 0) {
            TextField("Buscar canción", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
            List(results) { result in
                Button {
                    onPick(result.song.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(result.song.title).font(.headline)
                        Text(result.song.artist).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
            }
            .padding()
        }
        .frame(width: 460, height: 520)
        .task(id: searchText) {
            let searchService = model.searchService
            let text = searchText
            results = await Task.detached {
                ((try? searchService.search(text)) ?? []).filter { $0.song.status == .ready }
            }.value
        }
    }
}
