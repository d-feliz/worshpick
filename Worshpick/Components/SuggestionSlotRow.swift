import SwiftUI
import WorshpickCore

struct SuggestionSlotRow: View {
    let slot: SuggestedSlot
    let song: Song?
    let alternatives: [Song]
    let onChooseAlternative: (UUID) -> Void
    let onSearch: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(slot.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if let song {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(song.title).font(.headline)
                        Text(song.artist).foregroundStyle(.secondary)
                    }
                    if !slot.reason.isEmpty {
                        Text(slot.reason).font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Sin sugerencia").foregroundStyle(.secondary).italic()
                }
            }
            Spacer()
            Menu {
                if !alternatives.isEmpty {
                    Section("Alternativas") {
                        ForEach(alternatives) { alternative in
                            Button("\(alternative.title) — \(alternative.artist)") { onChooseAlternative(alternative.id) }
                        }
                    }
                }
                Button("Buscar otra…", action: onSearch)
                if song != nil {
                    Button("Quitar", role: .destructive, action: onClear)
                }
            } label: {
                Text("Cambiar")
            }
            .fixedSize()
        }
        .padding(.vertical, 4)
    }
}
