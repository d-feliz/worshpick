import SwiftUI

struct VocabularyEditor: View {
    let title: String
    let values: [String]
    let onChange: ([String]) -> Void

    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            List {
                ForEach(values, id: \.self) { value in
                    HStack {
                        Text(value)
                        Spacer()
                        Button { onChange(values.filter { $0 != value }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                .onMove { source, destination in
                    var reordered = values
                    reordered.move(fromOffsets: source, toOffset: destination)
                    onChange(reordered)
                }
            }
            .listStyle(.bordered)
            HStack {
                TextField("Nuevo valor", text: $newValue).onSubmit(addValue)
                Button("Añadir", action: addValue).disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Las canciones ya analizadas conservan sus valores. Reanalízalas para usar la lista nueva.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addValue() {
        let trimmedValue = newValue.trimmingCharacters(in: .whitespaces)
        guard !trimmedValue.isEmpty, !values.contains(trimmedValue) else { return }
        onChange(values + [trimmedValue])
        newValue = ""
    }
}
