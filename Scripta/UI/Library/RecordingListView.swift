import SwiftData
import SwiftUI

/// The middle column: recordings matching the sidebar filter and the search.
struct RecordingListView: View {
    @Environment(AppModel.self) private var appModel
    @Query private var recordings: [Recording]
    @Query(sort: [SortDescriptor(\Folder.name, comparator: .localizedStandard)]) private var folders: [Folder]

    let item: SidebarItem
    @Binding var sortField: LibrarySortField
    @Binding var sortAscending: Bool
    let searchText: String
    @Binding var selection: UUID?

    @State private var renameTarget: Recording?
    @State private var renameText = ""
    @State private var deleteTarget: Recording?

    init(
        item: SidebarItem,
        sortField: Binding<LibrarySortField>,
        sortAscending: Binding<Bool>,
        searchText: String,
        selection: Binding<UUID?>
    ) {
        self.item = item
        _sortField = sortField
        _sortAscending = sortAscending
        self.searchText = searchText
        _selection = selection
        _recordings = Query(sort: sortField.wrappedValue.descriptors(ascending: sortAscending.wrappedValue))
    }

    var body: some View {
        // Filtering happens in memory: it includes transcript text and keeps
        // sidebar counts and list contents on the same rules.
        let visible = recordings.filter { item.matches($0) && $0.matches(searchText: searchText) }

        List(selection: $selection) {
            ForEach(visible) { recording in
                RecordingRow(recording: recording)
                    .tag(recording.id)
                    // Drag onto a folder in the sidebar to file it there.
                    .draggable(recording.id.uuidString)
                    // Not `role: .destructive`: that would hide the row before the user confirms.
                    .swipeActions(edge: .trailing) {
                        Button("Löschen", systemImage: "trash") { deleteTarget = recording }
                            .tint(.red)
                    }
            }
        }
        // Double-click or Return plays the recording.
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let recording = visible.first(where: { ids.contains($0.id) }) {
                contextMenu(for: recording)
            }
        } primaryAction: { ids in
            if let recording = visible.first(where: { ids.contains($0.id) }) {
                appModel.play(recording)
            }
        }
        .overlay {
            if visible.isEmpty {
                emptyState
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let status = appModel.importStatus {
                    ImportStatusView(status: status)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if appModel.recorder.isActive || appModel.isSavingRecording {
                    RecordingCapsuleView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(12)
        }
        .animation(.smooth, value: appModel.recorder.isActive || appModel.isSavingRecording)
        .animation(.smooth, value: appModel.importStatus)
        .navigationTitle(title)
        .navigationSubtitle(Text("\(visible.count) Aufnahmen"))
        .onDeleteCommand {
            deleteTarget = visible.first { $0.id == selection }
        }
        .toolbar { toolbarContent }
        .task { appModel.refreshMeetingApps() }
        .alert("Aufnahme umbenennen", isPresented: isRenaming) {
            TextField("Titel", text: $renameText)
            Button("Umbenennen") {
                if let renameTarget {
                    appModel.rename(renameTarget, to: renameText)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            "Aufnahme löschen?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { recording in
            Button("Löschen", role: .destructive) {
                appModel.delete(recording)
            }
        } message: { recording in
            Text("„\(recording.title)“ wird mit Transkript und Audiodateien endgültig gelöscht.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if appModel.recorder.isActive {
                Button("Aufnahme beenden", systemImage: "stop.circle.fill") {
                    appModel.stopRecording()
                }
                .foregroundStyle(.red)
                .help("Aufnahme beenden und speichern (⌘↩)")
            } else {
                Menu {
                    MicrophoneMenuSection()
                } label: {
                    Label("Neue Aufnahme", systemImage: "record.circle")
                } primaryAction: {
                    appModel.toggleRecording()
                }
                .help("Neue Aufnahme (⌘N)")

                Menu {
                    MeetingSourceMenu()
                    MicrophoneMenuSection(title: "Mikrofon („Ich“)")
                } label: {
                    Label("Meeting aufnehmen", systemImage: "person.2.wave.2")
                } primaryAction: {
                    Task { await appModel.startMeeting() }
                }
                .help("Meeting aufnehmen: Mikrofon und Systemaudio getrennt (⇧⌘N)")
            }
            Button("Importieren", systemImage: "square.and.arrow.down") {
                appModel.isImporterPresented = true
            }
            .help("Audio- oder Videodateien importieren (⌘I) – oder einfach ins Fenster ziehen")
        }
        ToolbarItem {
            Menu("Sortieren", systemImage: "arrow.up.arrow.down") {
                Picker("Sortieren nach", selection: $sortField) {
                    ForEach(LibrarySortField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                .pickerStyle(.inline)
                Picker("Reihenfolge", selection: $sortAscending) {
                    Text("Absteigend").tag(false)
                    Text("Aufsteigend").tag(true)
                }
                .pickerStyle(.inline)
            }
            .help("Sortierung ändern")
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for recording: Recording) -> some View {
        Button("Abspielen", systemImage: "play") {
            appModel.play(recording)
        }
        .disabled(appModel.library.audioURL(for: recording) == nil)
        if recording.status.isInProgress {
            Button("Transkription abbrechen", systemImage: "xmark.circle") {
                appModel.cancelTranscription(of: recording)
            }
        } else {
            Button(recording.status == .done ? "Erneut transkribieren" : "Transkribieren", systemImage: "text.bubble") {
                appModel.transcribe(recording)
            }
            .disabled(appModel.library.audioURL(for: recording) == nil)
        }
        Divider()
        Button("Umbenennen …", systemImage: "pencil") {
            renameText = recording.title
            renameTarget = recording
        }
        if recording.transcript.map({ !$0.segments.isEmpty }) == true {
            Button("Transkript kopieren", systemImage: "doc.on.doc") {
                appModel.copyTranscript(of: recording)
            }
            Menu("Exportieren", systemImage: "square.and.arrow.up") {
                ExportMenuItems(recording: recording)
            }
        }
        Menu("In Ordner", systemImage: "folder.badge.plus") {
            ForEach(folders) { folder in
                Button(folder.name) { appModel.move(recordingIDs: [recording.id], to: folder) }
                    .disabled(recording.folder?.id == folder.id)
            }
            if recording.folder != nil {
                Divider()
                Button("Aus dem Ordner nehmen") { appModel.move(recordingIDs: [recording.id], to: nil) }
            }
            if folders.isEmpty {
                Text("Noch keine Ordner – lege sie links mit + an.")
            }
        }
        Button("Im Finder zeigen", systemImage: "folder") {
            appModel.revealInFinder(recording)
        }
        .disabled(appModel.library.audioURL(for: recording) == nil)
        Divider()
        Button("Löschen …", systemImage: "trash", role: .destructive) {
            deleteTarget = recording
        }
    }

    private var title: Text {
        switch item {
        case .filter(let filter): Text(filter.title)
        case .folder(let id): Text(verbatim: folders.first { $0.id == id }?.name ?? "")
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if case .folder = item {
            ContentUnavailableView {
                Label("Ordner ist leer", systemImage: "folder")
            } description: {
                Text("Zieh Aufnahmen aus „Alle Aufnahmen“ oder Audiodateien aus dem Finder auf diesen Ordner links.")
            }
        } else if item == .all {
            ContentUnavailableView {
                Label("Noch keine Aufnahmen", systemImage: "waveform")
            } description: {
                Text("Starte eine Aufnahme mit ⌘N oder ziehe Audio- und Videodateien in dieses Fenster.")
            } actions: {
                Button("Neue Aufnahme") {
                    appModel.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                #if DEBUG
                Button("Beispieldaten laden") {
                    appModel.perform { try appModel.library.insertSampleData() }
                }
                #endif
            }
        } else if case .filter(let filter) = item {
            ContentUnavailableView {
                Label { Text(filter.title) } icon: { Image(systemName: filter.systemImage) }
            } description: {
                Text("Hier gibt es noch keine Aufnahmen.")
            }
        }
    }

    // MARK: - Bindings

    private var isRenaming: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }
}
