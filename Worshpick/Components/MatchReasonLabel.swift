import SwiftUI
import WorshpickCore

struct MatchReasonLabel: View {
    let matchReason: MatchReason

    var body: some View {
        switch matchReason {
        case .filtersOnly, .title:
            EmptyView()
        case .artist:
            reasonText(Text("Coincide el autor"))
        case .keyword(let keyword):
            reasonText(Text("Significado: ") + Text(keyword).bold())
        case .theme(let theme):
            reasonText(Text("Tema: ") + Text(theme).bold())
        case .summary:
            reasonText(Text("Coincide el resumen"))
        case .passage(let reference):
            reasonText(Text("Pasaje: ") + Text(reference.displayText).bold())
        case .lyricsSnippet(let snippet):
            reasonText(Self.highlightedSnippet(snippet))
        }
    }

    private func reasonText(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    /// SearchService marks matches with ⟦ ⟧; each marked part is shown in bold.
    static func highlightedSnippet(_ snippet: String) -> Text {
        let flattenedSnippet = snippet.replacingOccurrences(of: "\n", with: " / ")
        var result = Text("")
        var remaining = Substring(flattenedSnippet)
        while let start = remaining.range(of: SearchService.snippetHighlightStart) {
            result = result + Text(String(remaining[..<start.lowerBound]))
            remaining = remaining[start.upperBound...]
            guard let end = remaining.range(of: SearchService.snippetHighlightEnd) else { break }
            result = result + Text(String(remaining[..<end.lowerBound])).bold().foregroundColor(.primary)
            remaining = remaining[end.upperBound...]
        }
        return result + Text(String(remaining))
    }
}
