import AppKit
import SwiftData
import SwiftUI

/// Filter chips above the recording list: where a recording comes from and
/// the user's folders.
struct LibraryFilterBar: View {
    @Environment(AppModel.self) private var appModel
    @Binding var selection: SidebarItem?
    @Binding var sortField: LibrarySortField
    @Binding var sortAscending: Bool
    @Query private var recordings: [Recording]
    @Query(sort: [SortDescriptor(\Folder.name, comparator: .localizedStandard)]) private var folders: [Folder]

    @State private var isCreatingFolder = false
    @State private var folderName = ""
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?

    /// The filters that get a chip of their own.
    static let chips: [LibraryFilter] = [.all, .meetings, .microphone]
    /// The rarer filters in the list menu; the one in use shows as an extra chip.
    static let menuFilters: [LibraryFilter] = [.imports] + LibraryFilter.statusFilters

    var body: some View {
        let current = selection ?? .all

        HStack(spacing: 0) {
            chips(current: current)
            listMenu
                .padding(.trailing, 12)
        }
        .alert("Neuer Ordner", isPresented: $isCreatingFolder) {
            TextField("Name", text: $folderName)
            Button("Anlegen") { appModel.createFolder(named: folderName) }
                .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Ordner umbenennen", isPresented: $folderToRename.isPresent, presenting: folderToRename) { folder in
            TextField("Name", text: $folderName)
            Button("Umbenennen") {
                appModel.rename(folder, to: folderName)
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            "Ordner „\(folderToDelete?.name ?? "")“ löschen?",
            isPresented: $folderToDelete.isPresent,
            titleVisibility: .visible,
            presenting: folderToDelete
        ) { folder in
            Button("Ordner löschen", role: .destructive) {
                appModel.delete(folder)
            }
        } message: { _ in
            Text("Die Aufnahmen darin bleiben erhalten.")
        }
    }

    private func chips(current: SidebarItem) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if case .filter(let filter) = current, Self.menuFilters.contains(filter) {
                    Button(action: showAll) {
                        HStack(spacing: 4) {
                            Text(filter.title)
                            Image(systemName: "xmark")
                                .imageScale(.small)
                        }
                    }
                    .buttonStyle(FilterChipStyle(isActive: true))
                    .help("Filter aufheben")
                }
                ForEach(Self.chips) { filter in
                    let isActive = current == .filter(filter)
                    Button {
                        selection = .filter(filter)
                    } label: {
                        filter == .all ? Text("Alle") : Text(filter.title)
                    }
                    .buttonStyle(FilterChipStyle(isActive: isActive))
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
                folderMenu(current: current)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// Import, sorting and the rarer filters, pinned at the end of the chips.
    private var listMenu: some View {
        Menu {
            Button("Importieren …", systemImage: "square.and.arrow.down", action: showImporter)
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
            Picker("Nur zeigen", selection: menuFilter) {
                Text("Alle").tag(LibraryFilter?.none)
                ForEach(Self.menuFilters) { filter in
                    Text(filter.title).tag(LibraryFilter?.some(filter))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Liste", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
                .frame(width: 26, height: 26)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(FilterChipLabel.fill(isActive: false), in: .circle)
        .help("Importieren (⌘I), sortieren und filtern")
    }

    /// The menu's filter shown in the list, nil while a chip or a folder is on.
    private var menuFilter: Binding<LibraryFilter?> {
        Binding {
            if case .filter(let filter) = selection, Self.menuFilters.contains(filter) {
                filter
            } else {
                nil
            }
        } set: { filter in
            selection = filter.map { .filter($0) } ?? .all
        }
    }

    private func showImporter() {
        appModel.isImporterPresented = true
    }

    /// The last chip: the folders as a menu. It carries the folder's name while one is shown.
    private func folderMenu(current: SidebarItem) -> some View {
        let shown = folders.first { current == .folder($0.id) }

        return Menu {
            ForEach(folders) { folder in
                Button {
                    selection = .folder(folder.id)
                } label: {
                    Label(folder.name, systemImage: folder.id == shown?.id ? "checkmark" : "folder")
                }
                .badge(recordings.count { $0.folder?.id == folder.id })
            }
            if !folders.isEmpty {
                Divider()
            }
            Button("Neuer Ordner …", systemImage: "folder.badge.plus", action: startCreatingFolder)
            if let shown {
                Divider()
                Button("„\(shown.name)“ umbenennen …", systemImage: "pencil") {
                    folderName = shown.name
                    folderToRename = shown
                }
                Button("„\(shown.name)“ löschen …", systemImage: "trash", role: .destructive) {
                    folderToDelete = shown
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let shown {
                    Text(verbatim: shown.name)
                } else {
                    Text("Ordner")
                }
                Image(systemName: "chevron.down")
                    .imageScale(.small)
            }
            .modifier(FilterChipLabel(isActive: shown != nil))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(FilterChipLabel.fill(isActive: shown != nil), in: .capsule)
        .help("Ordner zeigen, anlegen oder ändern")
    }

    private func showAll() {
        selection = .all
    }

    private func startCreatingFolder() {
        folderName = ""
        isCreatingFolder = true
    }
}

/// Text, size and tap area of a filter chip.
struct FilterChipLabel: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .font(.callout.weight(isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .contentShape(.capsule)
    }

    /// Active chips are filled with the text color, like a pressed key.
    static func fill(isActive: Bool) -> Color {
        isActive ? Color.primary : Color.primary.opacity(0.08)
    }
}

/// A capsule that is filled while its filter is on.
struct FilterChipStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(FilterChipLabel(isActive: isActive))
            .background(FilterChipLabel.fill(isActive: isActive), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
