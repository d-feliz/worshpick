import SwiftUI
import WorshpickCore

struct IngestProgressBar: View {
    let progress: IngestProgress

    var body: some View {
        if progress.state == .running, progress.totalCount > 0 {
            HStack(spacing: 10) {
                ProgressView(value: Double(progress.completedCount), total: Double(progress.totalCount))
                    .frame(maxWidth: 220)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private var statusText: String {
        let position = min(progress.completedCount + 1, progress.totalCount)
        let phase = progress.analyzingSongIds.isEmpty ? "Leyendo letras" : "Analizando"
        return "\(phase) \(position) de \(progress.totalCount)"
    }
}
