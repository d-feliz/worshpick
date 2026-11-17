import SwiftUI
import WorshpickCore

struct SetlistsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var setlistPendingDeletion: Setlist?

    var body: some View {
        let setlists = loadSetlists()
        Group {
            if setlists.isEmpty {
                ContentUnavailableView {
                    Label("Sin setlists", systemImage: "list.bullet.rectangle")
                } actions: {
                    Button("Nuevo setlist") { model.createSetlist() }
                }
            } else {
                List(setlists, id: \.setlist.id) { setlistWithItems in
                    let setlist = setlistWithItems.setlist
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(setlist.serviceDate.formatted(date: .complete, time: .omitted)).font(.headline)
                            if !setlist.serviceDescription.isEmpty {
                                Text(setlist.serviceDescription).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("\(setlistWithItems.items.count) canciones").font(.caption).foregroundStyle(.secondary)
                        if setlist.status == .used {
                            TagChip(text: "Usado", tint: .green)
                        }
                        if model.currentSetlistId == setlist.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.currentSetlistId = setlist.id }
                    .contextMenu {
                        Button("Abrir en el panel") { model.currentSetlistId = setlist.id }
                        Button("Eliminar…", role: .destructive) { setlistPendingDeletion = setlist }
                    }
                }
            }
        }
        .navigationTitle("Setlists")
        .toolbar {
            ToolbarItem {
                Button { model.createSetlist() } label: { Label("Nuevo setlist", systemImage: "plus") }
            }
        }
        .confirmationDialog(
            "¿Eliminar este setlist?",
            isPresented: Binding(get: { setlistPendingDeletion != nil }, set: { if !$0 { setlistPendingDeletion = nil } })
        ) {
            Button("Eliminar", role: .destructive) {
                guard let setlist = setlistPendingDeletion else { return }
                model.perform { try model.setlistStore.deleteSetlist(id: setlist.id) }
                if model.currentSetlistId == setlist.id { model.currentSetlistId = nil }
                model.setlistDidChange()
                model.catalogDidChange()
            }
        } message: {
            Text("Si estaba marcado como usado, sus canciones dejan de contar en el historial.")
        }
    }

    private func loadSetlists() -> [SetlistWithItems] {
        _ = model.setlistRevision
        let setlists = (try? model.setlistStore.allSetlists()) ?? []
        return setlists.compactMap { try? model.setlistStore.setlist(id: $0.id) }
    }
}
