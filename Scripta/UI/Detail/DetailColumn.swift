import SwiftUI

/// The detail column: the selected recording, the running one, or a hint.
struct DetailColumn: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let recording = appModel.selectedRecording {
            RecordingDetailView(recording: recording)
        } else if let live = appModel.liveRecordings.first(where: { $0.id == appModel.selectedRecordingID }) {
            LiveRecordingDetailView(item: live)
        } else {
            ContentUnavailableView(
                "Keine Aufnahme ausgewählt",
                systemImage: "waveform",
                description: Text("Wähle eine Aufnahme aus der Liste.")
            )
        }
    }
}
