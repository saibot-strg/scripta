import SwiftData
import SwiftUI

/// Sidebar with library, source and status filters plus live counts.
struct SidebarView: View {
    @Binding var selection: LibraryFilter?
    @Query private var recordings: [Recording]

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
        }
        .navigationTitle("Scripta")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                UpdateFooter()
                ModelStatusFooter()
            }
        }
    }

    private func row(for filter: LibraryFilter) -> some View {
        Label {
            Text(filter.title)
        } icon: {
            Image(systemName: filter.systemImage)
        }
        .badge(recordings.count(where: filter.matches))
        .tag(filter)
    }
}
