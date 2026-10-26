import SwiftData
import SwiftUI

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
                    Button("Neuer Ordner", systemImage: "plus", action: startCreatingFolder)
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
        .alert("Ordner umbenennen", item: $folderToRename) { folder in
            TextField("Name", text: $folderName)
            Button("Umbenennen") {
                appModel.rename(folder, to: folderName)
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            "Ordner „\(folderToDelete?.name ?? "")“ löschen?",
            item: $folderToDelete,
            titleVisibility: .visible
        ) { folder in
            Button("Ordner löschen", role: .destructive) {
                appModel.delete(folder)
            }
        } message: { _ in
            Text("Die Aufnahmen darin bleiben erhalten.")
        }
    }

    private func startCreatingFolder() {
        folderName = ""
        isCreatingFolder = true
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
