import SwiftUI

/// The settings window, one tab per area.
struct SettingsView: View {
    enum Pane: String, Hashable {
        case general, recording, transcription, people, dictation, permissions
    }

    @State private var pane: Pane

    init(pane: Pane = .general) {
        _pane = State(initialValue: pane)
    }

    var body: some View {
        TabView(selection: $pane) {
            Tab("Allgemein", systemImage: "gearshape", value: .general) {
                GeneralSettingsView()
            }
            Tab("Aufnahme", systemImage: "mic", value: .recording) {
                RecordingSettingsView()
            }
            Tab("Transkription", systemImage: "text.bubble", value: .transcription) {
                TranscriptionSettingsView()
            }
            Tab("Personen", systemImage: "person.2", value: .people) {
                PeopleSettingsView()
            }
            Tab("Diktat", systemImage: "mic.badge.plus", value: .dictation) {
                DictationSettingsView()
            }
            Tab("Berechtigungen", systemImage: "lock.shield", value: .permissions) {
                PermissionsSettingsView()
            }
        }
        .frame(width: 520)
    }
}
