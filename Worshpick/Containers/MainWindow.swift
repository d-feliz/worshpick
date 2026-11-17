import SwiftUI
import WorshpickCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case library, suggest, setlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Biblioteca"
        case .suggest: "Sugerir"
        case .setlists: "Setlists"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "music.note.list"
        case .suggest: "sparkles"
        case .setlists: "list.bullet.rectangle"
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selectedSection: SidebarSection = Self.initialSection
    @State private var isSetlistPanelVisible = true

    private static var initialSection: SidebarSection {
        #if DEBUG
        DebugSnapshot.initialSection ?? .library
        #else
        .library
        #endif
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                ClaudeStatusBanner()
                switch selectedSection {
                case .library: LibraryScreen()
                case .suggest: SuggestScreen()
                case .setlists: SetlistsScreen()
                }
            }
            .inspector(isPresented: $isSetlistPanelVisible) {
                SetlistPanel()
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 460)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSetlistPanelVisible.toggle()
                    } label: {
                        Label("Setlist", systemImage: "sidebar.trailing")
                    }
                    .help("Mostrar u ocultar el setlist")
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 620)
        .alert("Algo salió mal", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
