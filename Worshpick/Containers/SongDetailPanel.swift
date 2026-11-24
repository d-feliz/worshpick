import AVKit
import SwiftUI
import WorshpickCore

struct SongDetailPanel: View {
    @Environment(AppModel.self) private var model
    let song: Song

    @State private var player: AVPlayer?
    @State private var titleDraft = ""
    @State private var artistDraft = ""
    @State private var themesDraft = ""
    @State private var keywordsDraft = ""
    @State private var passagesDraft = ""
    @State private var lyricsDraft = ""
    @State private var isEditingLyrics = false
    @State private var passages: [Passage] = []
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                videoPreview
                if song.needsReview { needsReviewNotice }
                if song.status != .ready { statusNotice }
                identitySection
                tagsSection
                passagesSection
                lyricsSection
            }
            .padding()
        }
        .background(.background)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Reanalizar") { Task { await model.reanalyze(song.id) } }
                    Button("Reprocesar con Claude OCR") { Task { await model.reprocessWithClaudeOCR(song.id) } }
                    if song.status == .failed {
                        Button("Reintentar") { Task { await model.retry(song.id) } }
                    }
                    Divider()
                    Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.videoURL(for: song)]) }
                    Button("Eliminar de la biblioteca…", role: .destructive) { isDeleteConfirmationPresented = true }
                } label: {
                    Label("Acciones", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("¿Eliminar \"\(song.title)\"?", isPresented: $isDeleteConfirmationPresented) {
            Button("Eliminar", role: .destructive) { model.deleteSongs(withIds: [song.id]) }
        } message: {
            Text("Se borra el video de la biblioteca de Worshpick. El archivo original no se toca.")
        }
        .task(id: song.id) { loadDrafts() }
        .onChange(of: song) { loadDrafts() }
    }

    // MARK: Sections

    private var videoPreview: some View {
        VideoPlayer(player: player)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .task(id: song.id) {
                let videoURL = model.videoURL(for: song)
                player = FileManager.default.fileExists(atPath: videoURL.path) ? AVPlayer(url: videoURL) : nil
            }
    }

    private var needsReviewNotice: some View {
        HStack(alignment: .top) {
            Image(systemName: "eye.trianglebadge.exclamationmark").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Revisa esta canción").font(.headline)
                Text("El OCR leyó poco texto o con poca confianza. Claude puede leer los fotogramas directamente.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Reprocesar con Claude OCR") { Task { await model.reprocessWithClaudeOCR(song.id) } }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusNotice: some View {
        HStack {
            if song.status == .failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(DisplayFormatting.status(song)).font(.callout)
            Spacer()
            if song.status == .failed {
                Button("Reintentar") { Task { await model.retry(song.id) } }
            }
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Título", text: $titleDraft)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .onSubmit { saveIfChanged(titleDraft, original: song.title) { .title($0) } }
            TextField("Autor", text: $artistDraft)
                .foregroundStyle(.secondary)
                .textFieldStyle(.plain)
                .onSubmit { saveIfChanged(artistDraft, original: song.artist) { .artist($0) } }
            Text(song.summary).font(.callout).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { languageAndEnergyPickers }
                VStack(alignment: .leading, spacing: 6) { languageAndEnergyPickers }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var languageAndEnergyPickers: some View {
        Picker("Idioma", selection: Binding(get: { song.language ?? .es }, set: { model.saveManualEdit(songId: song.id, .language($0)) })) {
            ForEach(SongLanguage.allCases, id: \.self) { Text(DisplayFormatting.language($0)).tag($0) }
        }
        .fixedSize()
        Picker("Energía", selection: Binding(get: { song.energy ?? .medium }, set: { model.saveManualEdit(songId: song.id, .energy($0)) })) {
            ForEach(Energy.allCases, id: \.self) { Text(DisplayFormatting.energy($0)).tag($0) }
        }
        .fixedSize()
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            vocabularyRow("Invitación", values: song.invitations, vocabulary: model.settings.invitationVocabulary) { .invitations($0) }
            vocabularyRow("Momento", values: song.moments, vocabulary: model.settings.momentVocabulary) { .moments($0) }
            commaSeparatedField("Temas", text: $themesDraft, original: song.themes) { .themes($0) }
            commaSeparatedField("Significado (palabras clave)", text: $keywordsDraft, original: song.keywords) { .keywords($0) }
        }
    }

    private var passagesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pasajes").font(.caption).foregroundStyle(.secondary)
            TextField("Romanos 8:38-39; Salmos 23", text: $passagesDraft)
                .onSubmit(savePassages)
        }
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Letra").font(.headline)
                Spacer()
                if isEditingLyrics {
                    Button("Cancelar") { lyricsDraft = song.lyrics; isEditingLyrics = false }
                    Button("Guardar") {
                        saveIfChanged(lyricsDraft, original: song.lyrics) { .lyrics($0) }
                        isEditingLyrics = false
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Editar") { isEditingLyrics = true }
                }
            }
            .controlSize(.small)
            if isEditingLyrics {
                TextEditor(text: $lyricsDraft)
                    .font(.body)
                    .frame(minHeight: 260)
            } else {
                LyricsView(lyrics: song.lyrics)
            }
        }
    }

    // MARK: Editing helpers

    private func vocabularyRow(_ title: String, values: [String], vocabulary: [String], edit: @escaping ([String]) -> ManualSongEdit) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            Menu {
                ForEach(vocabulary, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: { values.contains(option) },
                        set: { isSelected in
                            let updatedValues = isSelected ? values + [option] : values.filter { $0 != option }
                            model.saveManualEdit(songId: song.id, edit(updatedValues))
                        }
                    ))
                }
            } label: {
                Text(values.isEmpty ? "Elegir…" : values.joined(separator: ", "))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commaSeparatedField(_ title: String, text: Binding<String>, original: [String], edit: @escaping ([String]) -> ManualSongEdit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text, axis: .vertical)
                .lineLimit(1...4)
                .onSubmit {
                    let values = text.wrappedValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if values != original { model.saveManualEdit(songId: song.id, edit(values)) }
                }
        }
    }

    private func saveIfChanged(_ value: String, original: String, edit: (String) -> ManualSongEdit) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue != original else { return }
        model.saveManualEdit(songId: song.id, edit(trimmedValue))
    }

    private func savePassages() {
        let existingKindByReference = Dictionary(passages.map { ($0.reference, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let references = BibleReferenceParser.parse(passagesDraft.replacingOccurrences(of: ";", with: " ")).references
        let drafts = references.map { PassageDraft(reference: $0, kind: existingKindByReference[$0] ?? .allusion) }
        guard drafts.map(\.reference) != passages.map(\.reference) else { return }
        model.saveManualEdit(songId: song.id, .passages(drafts))
        loadDrafts()
    }

    private func loadDrafts() {
        titleDraft = song.title
        artistDraft = song.artist
        themesDraft = song.themes.joined(separator: ", ")
        keywordsDraft = song.keywords.joined(separator: ", ")
        if !isEditingLyrics { lyricsDraft = song.lyrics }
        passages = (try? model.catalogStore.passages(forSongId: song.id)) ?? []
        passagesDraft = passages.map(\.reference.displayText).joined(separator: "; ")
    }
}
