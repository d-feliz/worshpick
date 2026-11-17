import SwiftUI
import UniformTypeIdentifiers
import WorshpickCore

struct LibraryScreen: View {
    private struct SearchKey: Equatable {
        var text: String
        var filters: SearchFilters
        var catalogRevision: Int
        var setlistRevision: Int
    }

    @Environment(AppModel.self) private var model
    @State private var searchText = Self.initialSearchText
    @State private var filters = SearchFilters()
    @State private var results: [SearchResult] = []
    @State private var themeOptions: [String] = []
    @State private var selectedSongId: UUID?
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false

    private static var initialSearchText: String {
        #if DEBUG
        DebugSnapshot.initialSearchText ?? ""
        #else
        ""
        #endif
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SearchFilterChips(
                filters: $filters,
                invitationOptions: model.settings.invitationVocabulary,
                themeOptions: themeOptions,
                momentOptions: model.settings.momentVocabulary
            )
            Divider()
            IngestProgressBar(progress: model.ingestProgress)
            HSplitView {
                resultsList
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                if let selectedSongId, let song = results.first(where: { $0.song.id == selectedSongId })?.song ?? model.song(id: selectedSongId) {
                    SongDetailPanel(song: song)
                        .frame(minWidth: 320, idealWidth: 400, maxWidth: 560, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Biblioteca")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Título, autor, letra, tema, Romanos 8…")
        .toolbar {
            ToolbarItem {
                Button { isImporterPresented = true } label: { Label("Importar…", systemImage: "square.and.arrow.down") }
                    .help("Importar videos de letras")
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let fileURLs) = result {
                Task { await model.importFiles(fileURLs) }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.06))
                    .overlay(Label("Suelta los videos para importarlos", systemImage: "square.and.arrow.down").font(.title2))
                    .padding(8)
            }
        }
        .alert("Importación terminada", isPresented: Binding(get: { model.importSummary != nil }, set: { if !$0 { model.importSummary = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(importSummaryDetails)
        }
        .task(id: SearchKey(text: searchText, filters: filters, catalogRevision: model.catalogRevision, setlistRevision: model.setlistRevision)) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            emptyState
        } else {
            List(selection: $selectedSongId) {
                ForEach(results) { result in
                    SongRow(result: result) { model.addToCurrentSetlist(songIds: [result.song.id]) }
                        .tag(result.song.id)
                        .draggable(SongDragItem(songIds: [result.song.id])) {
                            Label(result.song.title, systemImage: "music.note")
                        }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let hasQuery = !searchText.trimmingCharacters(in: .whitespaces).isEmpty || !filters.isEmpty
        if hasQuery {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label("Tu catálogo está vacío", systemImage: "film.stack")
            } description: {
                Text("Arrastra aquí tus videos de letras o usa Importar. Worshpick lee la letra y etiqueta cada canción.")
            } actions: {
                Button("Importar videos…") { isImporterPresented = true }
            }
        }
    }

    private var importSummaryDetails: String {
        guard let summary = model.importSummary else { return "" }
        var lines = [summary.message + "."]
        if !summary.duplicateFileNames.isEmpty {
            lines.append("Ya estaban en la biblioteca: " + summary.duplicateFileNames.joined(separator: ", "))
        }
        lines += summary.failureMessages
        return lines.joined(separator: "\n")
    }

    private func runSearch() async {
        let isTyping = !searchText.isEmpty
        if isTyping {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
        }
        let searchService = model.searchService
        let catalogStore = model.catalogStore
        let text = searchText
        let currentFilters = filters
        let found = await Task.detached(priority: .userInitiated) {
            (try? searchService.search(text, filters: currentFilters)) ?? []
        }.value
        let themes = (try? catalogStore.existingThemes()) ?? []
        guard !Task.isCancelled else { return }
        results = found
        themeOptions = themes
        #if DEBUG
        if DebugSnapshot.selectsFirstResult, selectedSongId == nil { selectedSongId = found.first?.song.id }
        #endif
    }

    private func loadDroppedFiles(from providers: [NSItemProvider]) {
        Task {
            var fileURLs: [URL] = []
            for provider in providers {
                if let fileURL = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: fileURL, relativeTo: nil) {
                    fileURLs.append(url)
                }
            }
            await model.importFiles(fileURLs)
        }
    }
}
