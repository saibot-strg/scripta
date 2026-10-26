import AppKit
import SwiftData
import SwiftUI

/// Main window: sidebar (filters), recording list and detail, like Mail or Notes.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            DetailColumn()
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
                    .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: appModel.toast)
        .animation(.smooth(duration: 0.2), value: isDropTargeted)
        .onAppear { appModel.attachUndoManager(undoManager) }
        .onChange(of: undoManager) { _, manager in appModel.attachUndoManager(manager) }
        .alert(appModel.presentedError?.title ?? "", isPresented: $appModel.presentedError.isPresent, presenting: appModel.presentedError) { error in
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
        .confirmationDialog("Erneut transkribieren?", isPresented: $appModel.retranscriptionRequest.isPresent, titleVisibility: .visible, presenting: appModel.retranscriptionRequest) { recording in
            Button("Erneut transkribieren", role: .destructive) {
                appModel.transcribe(recording)
            }
        } message: { recording in
            Text("Das Transkript von „\(recording.title)“ wird neu erstellt. Deine Textkorrekturen und vergebenen Namen gehen dabei verloren; bekannte Stimmen schlägt Scripta wieder vor.")
        }
    }
}

#if DEBUG
#Preview(traits: .sampleLibrary) {
    ContentView()
        .frame(width: 1180, height: 760)
}
#endif
