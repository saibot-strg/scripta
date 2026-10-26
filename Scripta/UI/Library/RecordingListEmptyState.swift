import SwiftUI

/// What the list shows when nothing matches the filter or the search.
struct RecordingListEmptyState: View {
    @Environment(AppModel.self) private var appModel
    let item: SidebarItem
    let searchText: String

    var body: some View {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search
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
                Button("Neue Aufnahme", action: appModel.toggleRecording)
                    .buttonStyle(.borderedProminent)
                #if DEBUG
                Button("Beispieldaten laden", action: insertSampleData)
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

    #if DEBUG
    private func insertSampleData() {
        appModel.perform { try appModel.library.insertSampleData() }
    }
    #endif
}
