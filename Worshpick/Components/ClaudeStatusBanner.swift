import SwiftUI
import WorshpickCore

struct ClaudeStatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if case .paused(let reason) = model.ingestProgress.state {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("La importación está en pausa").font(.headline)
                    Text(reason).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Reanudar") { Task { await model.resumeIngest() } }
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
        }
    }
}
