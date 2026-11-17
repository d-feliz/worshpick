import SwiftUI
import WorshpickCore

@main
struct WorshpickApp: App {
    @State private var loadResult: Result<AppModel, Error>

    init() {
        _loadResult = State(initialValue: Result { try AppModel.makeLive() })
    }

    var body: some Scene {
        WindowGroup("Worshpick") {
            switch loadResult {
            case .success(let model):
                #if DEBUG
                if DebugSnapshot.showsSetlistPanelOnly {
                    SetlistPanel()
                        .environment(model)
                        .frame(width: 380, height: 640)
                        .task { await DebugSnapshot.captureWhenReady() }
                } else {
                    mainWindow(model)
                }
                #else
                mainWindow(model)
                #endif
            case .failure(let error):
                ContentUnavailableView("No se pudo abrir la biblioteca", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
                    .frame(minWidth: 500, minHeight: 300)
            }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            if case .success(let model) = loadResult {
                WorshpickCommands(model: model)
            }
        }

        Settings {
            if case .success(let model) = loadResult {
                SettingsScreen()
                    .environment(model)
            }
        }
    }
}

extension WorshpickApp {
    private func mainWindow(_ model: AppModel) -> some View {
        MainWindow()
            .environment(model)
            .task { await model.start() }
            #if DEBUG
            .task { await DebugSnapshot.captureWhenReady() }
            #endif
    }
}

struct WorshpickCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nuevo setlist") { model.createSetlist() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        #if DEBUG
        CommandMenu("Depuración") {
            Button("Cargar catálogo de prueba") { model.loadSampleCatalog() }
        }
        #endif
    }
}
