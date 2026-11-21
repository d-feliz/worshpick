import SwiftUI
import WorshpickCore

struct SuggestScreen: View {
    @Environment(AppModel.self) private var model
    @State private var serviceDescription = ""
    @State private var serviceDate = AppModel.nextSunday()
    @State private var selectedTemplateId: UUID?
    @State private var songCount = 5
    @State private var suggestionTask: Task<Void, Never>?
    @State private var slotBeingReplaced: Int?

    private var isSuggesting: Bool { suggestionTask != nil }

    var body: some View {
        @Bindable var model = model
        MainContentWithSidePanel(sidePanelMaximumWidth: 440, sidePanelEdge: .leading) {
            results
        } sidePanel: {
            form
        }
        .navigationTitle("Sugerir canciones")
        .onAppear {
            if selectedTemplateId == nil { selectedTemplateId = model.settings.serviceTemplates.first?.id }
            songCount = model.settings.defaultSongCount
        }
        .sheet(item: Binding(get: { slotBeingReplaced.map(IdentifiedIndex.init) }, set: { slotBeingReplaced = $0?.index })) { identifiedSlot in
            SongPickerSheet { pickedSongId in
                replaceSong(inSlot: identifiedSlot.index, with: pickedSongId)
            }
        }
    }

    private var form: some View {
        Form {
            Section("Servicio") {
                TextField("De qué va el servicio", text: $serviceDescription, prompt: Text("Pasajes, idea principal, ocasión… p. ej. Romanos 8: nada nos separa del amor de Dios"), axis: .vertical)
                    .lineLimit(4...10)
                DatePicker("Fecha", selection: $serviceDate, displayedComponents: .date)
            }
            Section("Estructura") {
                Picker("Plantilla", selection: $selectedTemplateId) {
                    ForEach(model.settings.serviceTemplates) { template in
                        Text("\(template.name) (\(template.slots.count))").tag(Optional(template.id))
                    }
                    Text("Sin plantilla").tag(UUID?.none)
                }
                if selectedTemplateId == nil {
                    Stepper("Canciones: \(songCount)", value: $songCount, in: 1...12)
                }
                if model.settings.avoidRepeatsSundayCount > 0 {
                    Text("Se evitan las canciones usadas en los últimos \(model.settings.avoidRepeatsSundayCount) domingos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    if isSuggesting {
                        ProgressView().controlSize(.small)
                        Text("Claude está eligiendo…").foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancelar") { suggestionTask?.cancel(); suggestionTask = nil }
                    } else {
                        Spacer()
                        Button("Sugerir") { startSuggestion() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(serviceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var results: some View {
        if let draft = model.suggestionDraft {
            VStack(spacing: 0) {
                List {
                    ForEach(draft.slots) { slot in
                        SuggestionSlotRow(
                            slot: slot,
                            song: slot.songId.flatMap(model.song(id:)),
                            alternatives: slot.alternativeSongIds.compactMap(model.song(id:)),
                            onChooseAlternative: { replaceSong(inSlot: slot.slotIndex, with: $0) },
                            onSearch: { slotBeingReplaced = slot.slotIndex },
                            onClear: { clearSlot(slot.slotIndex) }
                        )
                    }
                }
                .listStyle(.inset)
                Divider()
                HStack {
                    Text(draft.serviceDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Crear setlist") { model.createSetlist(from: draft) }
                        .disabled(!draft.slots.contains(where: \.hasSuggestion))
                }
                .padding(10)
            }
        } else {
            ContentUnavailableView(
                "Describe el servicio", systemImage: "sparkles",
                description: Text("Claude elige canciones de tu catálogo según los pasajes y la idea principal. Después puedes cambiar cada una.")
            )
        }
    }

    private func startSuggestion() {
        let template = model.settings.serviceTemplates.first { $0.id == selectedTemplateId }
        let request = SuggestionRequest(serviceDescription: serviceDescription, serviceDate: serviceDate, template: template, songCount: songCount)
        let suggester = model.suggester
        suggestionTask = Task {
            do {
                let draft = try await suggester.suggest(request)
                if !Task.isCancelled { model.suggestionDraft = draft }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { model.errorMessage = error.localizedDescription }
            }
            suggestionTask = nil
        }
    }

    private func replaceSong(inSlot slotIndex: Int, with songId: UUID) {
        guard var draft = model.suggestionDraft, draft.slots.indices.contains(slotIndex) else { return }
        let previousSongId = draft.slots[slotIndex].songId
        draft.slots[slotIndex].songId = songId
        draft.slots[slotIndex].reason = "Elegida a mano"
        draft.slots[slotIndex].alternativeSongIds = draft.slots[slotIndex].alternativeSongIds.filter { $0 != songId } + [previousSongId].compactMap { $0 }
        model.suggestionDraft = draft
    }

    private func clearSlot(_ slotIndex: Int) {
        guard var draft = model.suggestionDraft, draft.slots.indices.contains(slotIndex) else { return }
        draft.slots[slotIndex].songId = nil
        draft.slots[slotIndex].reason = ""
        model.suggestionDraft = draft
    }
}

private struct IdentifiedIndex: Identifiable {
    let index: Int
    var id: Int { index }
}
