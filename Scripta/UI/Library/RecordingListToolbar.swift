import SwiftUI

/// Above the recording list: record, and record a meeting. Importing, sorting
/// and the rarer filters sit next to the filter chips.
struct RecordingListToolbar: ToolbarContent {
    @Environment(AppModel.self) private var appModel

    var body: some ToolbarContent {
        ToolbarItemGroup {
            if appModel.recorder.isActive {
                Button("Aufnahme beenden", systemImage: "stop.circle.fill", action: stopRecording)
                    .foregroundStyle(.recording)
                    .help("Aufnahme beenden und speichern (⌘↩)")
            } else {
                Menu {
                    MicrophoneMenuSection()
                } label: {
                    Label("Aufnehmen", systemImage: "waveform")
                } primaryAction: {
                    appModel.toggleRecording()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
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
        }
    }

    private func stopRecording() {
        appModel.stopRecording()
    }
}
