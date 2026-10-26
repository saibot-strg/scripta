import SwiftUI

/// Recording, meeting, import and sorting in the list's toolbar.
struct RecordingListToolbar: ToolbarContent {
    @Environment(AppModel.self) private var appModel
    @Binding var sortField: LibrarySortField
    @Binding var sortAscending: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            if appModel.recorder.isActive {
                Button("Aufnahme beenden", systemImage: "stop.circle.fill", action: stopRecording)
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
            Button("Importieren", systemImage: "square.and.arrow.down", action: showImporter)
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

    private func stopRecording() {
        appModel.stopRecording()
    }

    private func showImporter() {
        appModel.isImporterPresented = true
    }
}
