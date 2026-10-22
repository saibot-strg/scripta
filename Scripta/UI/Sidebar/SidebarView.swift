import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar with library, source and status filters, the user's folders and
/// live counts.
struct SidebarView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var selection: SidebarItem?
    @Query private var recordings: [Recording]
    @Query(sort: [SortDescriptor(\Folder.name, comparator: .localizedStandard)]) private var folders: [Folder]

    @State private var isCreatingFolder = false
    @State private var folderName = ""
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?

    var body: some View {
        List(selection: $selection) {
            Section("Bibliothek") {
                ForEach(LibraryFilter.libraryFilters) { row(for: $0) }
            }
            Section("Quelle") {
                ForEach(LibraryFilter.sourceFilters) { row(for: $0) }
            }
            Section("Status") {
                ForEach(LibraryFilter.statusFilters) { row(for: $0) }
            }
            Section {
                ForEach(folders) { folder in
                    FolderRow(folder: folder, count: recordings.count { $0.folder?.id == folder.id })
                        .tag(SidebarItem.folder(folder.id))
                        .contextMenu {
                            Button("Umbenennen …", systemImage: "pencil") {
                                folderName = folder.name
                                folderToRename = folder
                            }
                            Button("Ordner löschen …", systemImage: "trash", role: .destructive) {
                                folderToDelete = folder
                            }
                        }
                }
                if folders.isEmpty {
                    Text("Ordner anlegen mit +, dann Aufnahmen hineinziehen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            } header: {
                HStack {
                    Text("Ordner")
                    Spacer()
                    Button("Neuer Ordner", systemImage: "plus") {
                        folderName = ""
                        isCreatingFolder = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Neuer Ordner")
                }
            }
        }
        .navigationTitle("Scripta")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                UpdateFooter()
                ModelStatusFooter()
            }
        }
        .alert("Neuer Ordner", isPresented: $isCreatingFolder) {
            TextField("Name", text: $folderName)
            Button("Anlegen") { appModel.createFolder(named: folderName) }
                .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Ordner umbenennen", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Name", text: $folderName)
            Button("Umbenennen") {
                if let folderToRename { appModel.rename(folderToRename, to: folderName) }
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            "Ordner „\(folderToDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ordner löschen", role: .destructive) {
                if let folderToDelete { appModel.delete(folderToDelete) }
            }
        } message: {
            Text("Die Aufnahmen darin bleiben erhalten.")
        }
    }

    private func row(for filter: LibraryFilter) -> some View {
        Label {
            Text(filter.title)
        } icon: {
            Image(systemName: filter.systemImage)
        }
        .badge(recordings.count(where: filter.matches))
        .tag(SidebarItem.filter(filter))
    }
}

/// A folder in the sidebar. Recordings dragged from the list are filed in it,
/// audio files dragged from the Finder are imported into it.
private struct FolderRow: View {
    @Environment(AppModel.self) private var appModel
    let folder: Folder
    let count: Int
    @State private var isTargeted = false

    var body: some View {
        Label(folder.name, systemImage: isTargeted ? "folder.fill" : "folder")
            .badge(count)
            .dropDestination(for: LibraryDrop.self) { items, _ in
                let recordingIDs = items.compactMap(\.recordingID)
                let files = items.compactMap(\.fileURL)
                appModel.move(recordingIDs: recordingIDs, to: folder)
                appModel.importFiles(files, into: folder)
                return !items.isEmpty
            } isTargeted: { isTargeted = $0 }
    }
}

/// What can be dropped on a folder: a recording from the list (its ID as
/// text) or a file from the Finder.
enum LibraryDrop: Transferable {
    case recording(UUID)
    case file(URL)

    var recordingID: UUID? {
        if case .recording(let id) = self { id } else { nil }
    }

    var fileURL: URL? {
        if case .file(let url) = self { url } else { nil }
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in LibraryDrop.file(url) })
        ProxyRepresentation(importing: { (text: String) in
            guard let id = UUID(uuidString: text) else { throw CocoaError(.fileReadCorruptFile) }
            return LibraryDrop.recording(id)
        })
    }
}
