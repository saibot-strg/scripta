import AppKit
import SwiftData
import SwiftUI

/// Main window: sidebar (filters), recording list and detail, like Mail or Notes.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("library.sortField") private var sortField: LibrarySortField = .date
    @AppStorage("library.sortAscending") private var sortAscending = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var appModel = appModel

        NavigationSplitView {
            SidebarView(selection: $appModel.sidebarSelection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            RecordingListView(
                item: appModel.sidebarSelection ?? .all,
                sortField: $sortField,
                sortAscending: $sortAscending,
                searchText: appModel.searchText,
                selection: $appModel.selectedRecordingID
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 500)
        } detail: {
            if let recording = appModel.selectedRecording {
                RecordingDetailView(recording: recording)
            } else {
                ContentUnavailableView(
                    "Keine Aufnahme ausgewählt",
                    systemImage: "waveform",
                    description: Text("Wähle eine Aufnahme aus der Liste.")
                )
            }
        }
        .searchable(text: $appModel.searchText, prompt: Text("Titel und Transkripte"))
        .searchFocused($isSearchFieldFocused)
        .onChange(of: appModel.searchFocusRequest) {
            isSearchFieldFocused = true
        }
        .playbackSpaceShortcut(appModel.player)
        .fileImporter(
            isPresented: $appModel.isImporterPresented,
            allowedContentTypes: AudioImporter.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { appModel.importFiles(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            appModel.importFiles(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                DropOverlay()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = appModel.toast {
                ToastView(message: toast)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: appModel.toast)
        .animation(.smooth(duration: 0.2), value: isDropTargeted)
        .alert(
            appModel.presentedError?.title ?? "",
            isPresented: Binding(
                get: { appModel.presentedError != nil },
                set: { if !$0 { appModel.presentedError = nil } }
            ),
            presenting: appModel.presentedError
        ) { error in
            if let url = error.settingsURL {
                Button("Systemeinstellungen öffnen") {
                    NSWorkspace.shared.open(url)
                }
                Button("Abbrechen", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { error in
            if let message = error.message {
                Text(message)
            }
        }
    }
}

#if DEBUG
#Preview(traits: .sampleLibrary) {
    ContentView()
        .frame(width: 1180, height: 760)
}
#endif
