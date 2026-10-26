import SwiftUI

/// A folder in the sidebar. Recordings dragged from the list are filed in it,
/// audio files dragged from the Finder are imported into it.
struct FolderRow: View {
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
