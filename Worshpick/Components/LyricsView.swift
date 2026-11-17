import SwiftUI

struct LyricsView: View {
    let lyrics: String

    var body: some View {
        Text(lyrics.isEmpty ? "Sin letra todavía" : lyrics)
            .font(.body)
            .foregroundStyle(lyrics.isEmpty ? .secondary : .primary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
