import SwiftUI
import WorshpickCore

struct SettingsScreen: View {
    var body: some View {
        TabView {
            ClaudeSettingsTab().tabItem { Label("Claude", systemImage: "sparkles") }
            OCRSettingsTab().tabItem { Label("OCR", systemImage: "text.viewfinder") }
            VocabularySettingsTab().tabItem { Label("Vocabularios", systemImage: "tag") }
            SuggestionSettingsTab().tabItem { Label("Sugerencias", systemImage: "list.number") }
            LibrarySettingsTab().tabItem { Label("Biblioteca", systemImage: "externaldrive") }
        }
        .frame(width: 620, height: 480)
    }
}

private let modelAliases = ["haiku", "sonnet", "opus"]

private struct ClaudeSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var pathDraft = ""
    @State private var connectionTestResult: String?
    @State private var isTestingConnection = false

    var body: some View {
        Form {
            Section("CLI de Claude") {
                TextField("Ruta", text: $pathDraft, prompt: Text(detectedPath ?? "No encontrado"))
                    .onSubmit { model.updateSettings { $0.claudeBinaryPath = pathDraft.isEmpty ? nil : pathDraft } }
                Text("Déjalo vacío para buscarlo en ~/.local/bin, /opt/homebrew/bin y /usr/local/bin.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Probar conexión") { testConnection() }
                        .disabled(isTestingConnection)
                    if isTestingConnection { ProgressView().controlSize(.small) }
                    if let connectionTestResult { Text(connectionTestResult).font(.callout).textSelection(.enabled) }
                }
            }
            Section("Modelos") {
                modelPicker("Para importar", value: model.settings.analysisModel) { newModel in model.updateSettings { $0.analysisModel = newModel } }
                modelPicker("Para sugerir", value: model.settings.suggestionModel) { newModel in model.updateSettings { $0.suggestionModel = newModel } }
                Stepper(
                    "Canciones analizadas a la vez: \(model.settings.claudeConcurrency)",
                    value: Binding(get: { model.settings.claudeConcurrency }, set: { newValue in model.updateSettings { $0.claudeConcurrency = newValue } }),
                    in: 1...3
                )
            }
        }
        .formStyle(.grouped)
        .onAppear { pathDraft = model.settings.claudeBinaryPath ?? "" }
    }

    private var detectedPath: String? {
        ClaudeBinaryLocator(configuredPath: nil).locate()?.path
    }

    private func modelPicker(_ title: String, value: String, onChange: @escaping (String) -> Void) -> some View {
        Picker(title, selection: Binding(get: { value }, set: onChange)) {
            ForEach(modelAliases + (modelAliases.contains(value) ? [] : [value]), id: \.self) { Text($0).tag($0) }
        }
    }

    private func testConnection() {
        model.updateSettings { $0.claudeBinaryPath = pathDraft.isEmpty ? nil : pathDraft }
        isTestingConnection = true
        connectionTestResult = nil
        let claudeRunner = model.claudeRunner
        let testModel = model.settings.analysisModel
        Task {
            do {
                try await ClaudeConnectionTest.run(using: claudeRunner, model: testModel)
                connectionTestResult = "✓ Conectado"
            } catch {
                connectionTestResult = error.localizedDescription
            }
            isTestingConnection = false
        }
    }
}

private struct OCRSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Picker("Motor por defecto", selection: Binding(
                get: { model.settings.defaultOCREngine },
                set: { newEngine in model.updateSettings { $0.defaultOCREngine = newEngine } }
            )) {
                Text("Apple Vision (en el Mac, gratis)").tag(OCREngineKind.vision)
                Text("Claude (lee los fotogramas)").tag(OCREngineKind.claude)
            }
            .pickerStyle(.radioGroup)
            LabeledContent("Un fotograma cada") {
                HStack {
                    Slider(
                        value: Binding(get: { model.settings.frameInterval }, set: { newInterval in model.updateSettings { $0.frameInterval = newInterval } }),
                        in: 0.5...3, step: 0.5
                    )
                    Text(String(format: "%.1f s", model.settings.frameInterval)).monospacedDigit().frame(width: 44)
                }
            }
            Text("Cada canción también se puede reprocesar con Claude OCR desde su panel de detalle.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct VocabularySettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VocabularyEditor(title: "Invitaciones", values: model.settings.invitationVocabulary) { newValues in
                model.updateSettings { $0.invitationVocabulary = newValues }
            }
            VocabularyEditor(title: "Momentos del servicio", values: model.settings.momentVocabulary) { newValues in
                model.updateSettings { $0.momentVocabulary = newValues }
            }
        }
        .padding()
    }
}

private struct SuggestionSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Stepper(
                "Canciones por defecto: \(model.settings.defaultSongCount)",
                value: Binding(get: { model.settings.defaultSongCount }, set: { newCount in model.updateSettings { $0.defaultSongCount = newCount } }),
                in: 1...12
            )
            Stepper(
                model.settings.avoidRepeatsSundayCount == 0
                    ? "Evitar repeticiones: desactivado"
                    : "Evitar canciones usadas en los últimos \(model.settings.avoidRepeatsSundayCount) domingos",
                value: Binding(get: { model.settings.avoidRepeatsSundayCount }, set: { newCount in model.updateSettings { $0.avoidRepeatsSundayCount = newCount } }),
                in: 0...12
            )
            Section("Plantillas de servicio") {
                ServiceTemplateEditor(
                    templates: model.settings.serviceTemplates,
                    momentOptions: model.settings.momentVocabulary,
                    invitationOptions: model.settings.invitationVocabulary
                ) { newTemplates in
                    model.updateSettings { $0.serviceTemplates = newTemplates }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LibrarySettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var diskUsage: Int64 = 0

    var body: some View {
        Form {
            LabeledContent("Ubicación") {
                Text(model.libraryService.libraryFolder.path).textSelection(.enabled).lineLimit(2)
            }
            LabeledContent("Espacio usado") { Text(DisplayFormatting.byteCount(diskUsage)) }
            Button("Mostrar en Finder") { NSWorkspace.shared.open(model.libraryService.libraryFolder) }
        }
        .formStyle(.grouped)
        .task { diskUsage = model.libraryService.libraryDiskUsageInBytes() }
    }
}
