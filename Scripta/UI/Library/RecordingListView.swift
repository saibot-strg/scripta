import AppKit
import SwiftData
import SwiftUI

/// The list column: recordings matching the filter chips and the search, under
/// date headings, with the running recording framed at the top.
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
        // Date headings only make sense in date order.
        let sections = sortField == .date ? DateSections.group(visible, by: \.createdAt) : []
        @Bindable var model = appModel

        List(selection: $selection) {
            ForEach(live) { item in
                LiveRecordingRow(item: item)
                    .tag(item.id)
                    .quietSelection(selection == item.id)
            }
            if sortField == .date {
                ForEach(sections, id: \.id) { section in
                    Section {
                        ForEach(section.items) { recording in
                            row(for: recording, isUnderDateHeading: true)
                        }
                    } header: {
                        Text(verbatim: section.title)
                    }
                }
            } else {
                ForEach(visible) { recording in
                    row(for: recording, isUnderDateHeading: false)
                }
            }
        }
        // Double-click or Return plays the recording.
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let recording = visible.first(where: { ids.contains($0.id) }) {
                RecordingContextMenu(recording: recording, folders: folders, deleteTarget: $deleteTarget)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            LibraryFilterBar(selection: $model.sidebarSelection, sortField: $sortField, sortAscending: $sortAscending)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                UpdateFooter()
                ModelStatusFooter()
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
        }
        .animation(.smooth, value: isRecording)
        .animation(.smooth, value: appModel.importStatus)
        .navigationTitle(title)
        .navigationSubtitle(Text("\(visible.count) Aufnahmen"))
        .onDeleteCommand {
            deleteTarget = visible.first { $0.id == selection }
        }
        .toolbar { RecordingListToolbar() }
        // Room for the two record buttons above the list; hiding the list stays in the View menu.
        .toolbar(removing: .sidebarToggle)
        .task { appModel.refreshMeetingApps() }
        .confirmationDialog("Aufnahme löschen?", isPresented: $deleteTarget.isPresent, titleVisibility: .visible, presenting: deleteTarget) { recording in
            Button("Löschen", role: .destructive) {
                appModel.delete(recording)
            }
        } message: { recording in
            Text("„\(recording.title)“ wird mit dem Transkript gelöscht. Die Audiodateien landen im Papierkorb.")
        }
    }

    private func row(for recording: Recording, isUnderDateHeading: Bool) -> some View {
        RecordingRow(
            recording: recording,
            isUnderDateHeading: isUnderDateHeading,
            onRename: appModel.renamingRecordingID == recording.id ? { finishRenaming(recording, to: $0) } : nil
        )
        .tag(recording.id)
        .quietSelection(selection == recording.id)
        // Not `role: .destructive`: that would hide the row before the user confirms.
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash") { deleteTarget = recording }
                .tint(.red)
        }
    }

    private func finishRenaming(_ recording: Recording, to title: String?) {
        appModel.renamingRecordingID = nil
        if let title { appModel.rename(recording, to: title) }
    }

    private var title: Text {
        switch item {
        case .filter(let filter): Text(filter.title)
        case .folder(let id): Text(verbatim: folders.first { $0.id == id }?.name ?? "")
        }
    }
}

private extension View {
    /// The chosen row as a soft tint instead of the system's filled accent
    /// color. The system highlight is switched off for the whole list (see
    /// `SelectionHighlightRemover`); this draws the row's own.
    func quietSelection(_ isSelected: Bool) -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
                .padding(.horizontal, 8)
                .background(SelectionHighlightRemover())
        )
    }
}

/// Switches off the selection highlight of the table behind a SwiftUI list.
/// A custom row background alone is only drawn on top of that highlight, and
/// SwiftUI has no setting for it. Sits in a row background, from where the
/// table is an ancestor. Without a table (should SwiftUI change its list),
/// nothing happens and the system highlight stays.
private struct SelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.apply()
    }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            var ancestor = superview
            while let view = ancestor {
                if let table = view as? NSTableView {
                    if table.selectionHighlightStyle != .none {
                        table.selectionHighlightStyle = .none
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
