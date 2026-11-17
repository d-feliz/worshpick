import SwiftUI
import WorshpickCore

struct SearchFilterChips: View {
    @Binding var filters: SearchFilters
    let invitationOptions: [String]
    let themeOptions: [String]
    let momentOptions: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                multipleChoiceMenu("Invitación", options: invitationOptions, selection: $filters.invitations)
                multipleChoiceMenu("Tema", options: themeOptions, selection: $filters.themes)
                multipleChoiceMenu("Momento", options: momentOptions, selection: $filters.moments)
                multipleChoiceMenu(
                    "Energía", options: Energy.allCases, selection: $filters.energies, label: DisplayFormatting.energy
                )
                multipleChoiceMenu(
                    "Idioma", options: SongLanguage.allCases, selection: $filters.languages, label: DisplayFormatting.language
                )
                notUsedRecentlyMenu
                Toggle(isOn: $filters.needsReviewOnly) { Text("Revisar") }
                    .toggleStyle(.button)
                    .controlSize(.small)
                if !filters.isEmpty {
                    Button("Quitar filtros") { filters = SearchFilters() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private var notUsedRecentlyMenu: some View {
        Menu {
            Button("Sin filtro") { filters.notUsedInLastSundays = nil }
            ForEach([1, 2, 4, 8, 12], id: \.self) { sundayCount in
                Button("Últimos \(sundayCount) domingo\(sundayCount == 1 ? "" : "s")") { filters.notUsedInLastSundays = sundayCount }
            }
        } label: {
            chipLabel(
                filters.notUsedInLastSundays.map { "No usada en \($0) dom." } ?? "No usada recientemente",
                isActive: filters.notUsedInLastSundays != nil
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func multipleChoiceMenu<Option: Hashable>(
        _ title: String, options: [Option], selection: Binding<Set<Option>>, label: @escaping (Option) -> String = { "\($0)" }
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Toggle(label(option), isOn: Binding(
                    get: { selection.wrappedValue.contains(option) },
                    set: { isSelected in
                        if isSelected { selection.wrappedValue.insert(option) } else { selection.wrappedValue.remove(option) }
                    }
                ))
            }
            if !selection.wrappedValue.isEmpty {
                Divider()
                Button("Quitar") { selection.wrappedValue.removeAll() }
            }
        } label: {
            let selectedLabels = options.filter(selection.wrappedValue.contains).map(label)
            chipLabel(selectedLabels.isEmpty ? title : "\(title): \(selectedLabels.joined(separator: ", "))", isActive: !selectedLabels.isEmpty)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(options.isEmpty)
    }

    private func chipLabel(_ text: String, isActive: Bool) -> some View {
        Text(text)
            .font(.callout)
            .lineLimit(1)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    }
}
