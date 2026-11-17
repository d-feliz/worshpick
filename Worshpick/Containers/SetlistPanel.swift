import SwiftUI
import WorshpickCore

struct SetlistPanel: View {
    @Environment(AppModel.self) private var model
    @State private var descriptionDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            if let setlistWithItems = model.currentSetlist {
                header(for: setlistWithItems.setlist)
                Divider()
                if setlistWithItems.items.isEmpty {
                    ContentUnavailableView(
                        "Setlist vacío", systemImage: "music.note.list",
                        description: Text("Añade canciones con + o arrástralas desde la biblioteca.")
                    )
                    .dropDestination(for: SongDragItem.self) { droppedItems, _ in
                        model.addToCurrentSetlist(songIds: droppedItems.flatMap(\.songIds))
                        return true
                    }
                } else {
                    SetlistFileTable(
                        rows: fileRows(for: setlistWithItems),
                        onReorder: { orderedItemIds in model.updateSetlist { try $0.reorderItems(in: $1, orderedItemIds: orderedItemIds) } },
                        onDropSongs: { songIds, position in model.addToCurrentSetlist(songIds: songIds, at: position) },
                        onRemove: { itemIds in model.updateSetlist { store, setlistId in try itemIds.forEach { try store.removeItem(id: $0, from: setlistId) } } }
                    )
                    Divider()
                    Label("Arrastra los archivos a Proclaim. Selecciona varios con ⌘ o ⇧.", systemImage: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            } else {
                ContentUnavailableView {
                    Label("Sin setlist", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Crea un setlist para el próximo servicio.")
                } actions: {
                    Button("Nuevo setlist") { model.createSetlist() }
                }
            }
        }
    }

    private func header(for setlist: Setlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                setlistMenu(current: setlist)
                Spacer()
                if setlist.status == .used {
                    Label("Usado", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                }
            }
            DatePicker("Fecha", selection: Binding(
                get: { setlist.serviceDate },
                set: { newDate in model.updateSetlist { try $0.updateDetails(setlistId: $1, serviceDate: newDate, serviceDescription: setlist.serviceDescription) } }
            ), displayedComponents: .date)
            .controlSize(.small)
            TextField("Descripción del servicio", text: $descriptionDraft, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.updateSetlist { try $0.updateDetails(setlistId: $1, serviceDate: setlist.serviceDate, serviceDescription: descriptionDraft) }
                }
            HStack {
                if setlist.status == .draft {
                    Button("Marcar como usado") { model.updateSetlist { try $0.markAsUsed(setlistId: $1) } }
                        .help("El historial usa los setlists marcados como usados para evitar repeticiones")
                } else {
                    Button("Volver a borrador") { model.updateSetlist { try $0.markAsDraft(setlistId: $1) } }
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .task(id: setlist.id) { descriptionDraft = setlist.serviceDescription }
    }

    private func setlistMenu(current setlist: Setlist) -> some View {
        Menu {
            Button("Nuevo setlist") { model.createSetlist() }
            Divider()
            ForEach((try? model.setlistStore.allSetlists()) ?? []) { otherSetlist in
                Button(otherSetlist.serviceDate.formatted(date: .abbreviated, time: .omitted) + (otherSetlist.status == .used ? " ✓" : "")) {
                    model.currentSetlistId = otherSetlist.id
                }
            }
        } label: {
            Text("Setlist del \(setlist.serviceDate.formatted(date: .abbreviated, time: .omitted))").font(.headline)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func fileRows(for setlistWithItems: SetlistWithItems) -> [SetlistFileRow] {
        setlistWithItems.items.compactMap { item in
            guard let itemId = item.id, let song = model.song(id: item.songId) else { return nil }
            let fileURL = model.videoURL(for: song)
            return SetlistFileRow(
                itemId: itemId, songId: song.id, fileURL: fileURL, title: song.title, slotLabel: item.slotLabel,
                fileExists: FileManager.default.fileExists(atPath: fileURL.path)
            )
        }
    }
}
