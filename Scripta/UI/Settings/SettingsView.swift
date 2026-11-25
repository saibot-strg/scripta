import SwiftUI

/// The settings window: four panes.
struct SettingsView: View {
    enum Pane: String, Hashable {
        case general, recording, recognition, dictation

        /// Also accepts the names of panes that were merged into these four.
        init?(name: String) {
            switch name {
            case "transcription", "languageModel", "people": self = .recognition
            case "permissions": self = .general
            default: self.init(rawValue: name)
            }
        }
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
            Tab("Erkennung", systemImage: "waveform", value: .recognition) {
                RecognitionSettingsView()
            }
            Tab("Diktat", systemImage: "mic.badge.plus", value: .dictation) {
                DictationSettingsView()
            }
        }
        .frame(width: 520)
    }
}
