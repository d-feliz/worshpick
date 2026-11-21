import SwiftUI
import WorshpickCore

struct SongRow: View {
    let result: SearchResult
    let onAddToSetlist: () -> Void

    private var song: Song { result.song }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(song.title).font(.headline).lineLimit(1)
                    if !song.artist.isEmpty {
                        Text(song.artist).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if song.status == .ready {
                    HStack(spacing: 4) {
                        ForEach(song.invitations, id: \.self) { TagChip(text: $0) }
                        ForEach(song.moments, id: \.self) { TagChip(text: $0, tint: .teal) }
                        if song.needsReview { TagChip(text: "Revisar", tint: .orange) }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    MatchReasonLabel(matchReason: result.matchReason)
                } else {
                    Label(DisplayFormatting.status(song), systemImage: song.status == .failed ? "exclamationmark.triangle" : "hourglass")
                        .font(.callout)
                        .foregroundStyle(song.status == .failed ? .orange : .secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    if song.status == .ready {
                        Text("Energía \(DisplayFormatting.energy(song.energy).lowercased())")
                    }
                    Text(DisplayFormatting.duration(song.duration)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let lastUsedText = DisplayFormatting.lastUsed(result.lastUsedDate) {
                    Text(lastUsedText).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Button(action: onAddToSetlist) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Añadir al setlist")
            .disabled(song.status != .ready)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
