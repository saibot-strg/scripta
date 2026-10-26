import SwiftData
import SwiftUI

/// The middle column: recordings matching the sidebar filter and the search,
/// with the running recording framed at the top.
struct RecordingListView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let live = appModel.liveRecordings.filter { live in
            item.matches(live) && (searchText.isEmpty || live.title.localizedStandardContains(searchText))
        }
        let isRecording = appModel.recorder.isActive || appModel.isSavingRecording
        let slideIn = reduceMotion ? AnyTransition.opacity : .move(edge: .bottom).combined(with: .opacity)

        List(selection: $selection) {
            ForEach(live) { item in
                LiveRecordingRow(item: item)
                    .tag(item.id)
            }
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
                RecordingContextMenu(recording: recording, folders: folders, renameTarget: $renameTarget, renameText: $renameText, deleteTarget: $deleteTarget)
            }
        } primaryAction: { ids in
            if let recording = visible.first(where: { ids.contains($0.id) }) {
                appModel.play(recording)
            }
        }
        .animation(.smooth, value: live)
        .overlay {
            if visible.isEmpty && live.isEmpty {
                RecordingListEmptyState(item: item, searchText: searchText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let status = appModel.importStatus {
                    ImportStatusView(status: status)
                        .transition(slideIn)
                }
                if isRecording {
                    RecordingCapsuleView()
                        .transition(slideIn)
                }
            }
            .padding(12)
        }
        .animation(.smooth, value: isRecording)
        .animation(.smooth, value: appModel.importStatus)
        .navigationTitle(title)
        .navigationSubtitle(Text("\(visible.count) Aufnahmen"))
        .onDeleteCommand {
            deleteTarget = visible.first { $0.id == selection }
        }
        .toolbar { RecordingListToolbar(sortField: $sortField, sortAscending: $sortAscending) }
        .task { appModel.refreshMeetingApps() }
        .alert("Aufnahme umbenennen", isPresented: $renameTarget.isPresent, presenting: renameTarget) { recording in
            TextField("Titel", text: $renameText)
            Button("Umbenennen") {
                appModel.rename(recording, to: renameText)
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Aufnahme löschen?", isPresented: $deleteTarget.isPresent, titleVisibility: .visible, presenting: deleteTarget) { recording in
            Button("Löschen", role: .destructive) {
                appModel.delete(recording)
            }
        } message: { recording in
            Text("„\(recording.title)“ wird mit dem Transkript gelöscht. Die Audiodateien landen im Papierkorb.")
        }
    }

    private var title: Text {
        switch item {
        case .filter(let filter): Text(filter.title)
        case .folder(let id): Text(verbatim: folders.first { $0.id == id }?.name ?? "")
        }
    }
}
