import SwiftUI

/// Detail column for the running recording: timer, levels and controls.
/// Once saved, the finished recording (same ID) takes its place.
struct LiveRecordingDetailView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.autoTranscribe) private var autoTranscribe = false
    let item: LiveRecording

    var body: some View {
        let recorder = appModel.recorder
        let isRunning = !item.isSaving && recorder.activeRecordingID == item.id
        let isPaused = isRunning && recorder.state == .paused

        VStack(spacing: 28) {
            VStack(spacing: 10) {
                SourceIcon(source: item.source, size: 56)
                Text(item.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if isRunning {
                RecordingTimerText(recorder: recorder)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(isPaused ? .secondary : .primary)
                    .accessibilityLabel(Text(isPaused ? "Aufnahme pausiert" : "Aufnahme läuft"))

                LiveRecordingLevels(recorder: recorder, isMeeting: item.source == .meeting, isPaused: isPaused)
                    .frame(maxWidth: 360)

                LiveRecordingControls(isPaused: isPaused, isStarting: recorder.state == .starting)

                Text(autoTranscribe
                     ? "Nach dem Beenden wird die Aufnahme automatisch transkribiert."
                     : "Das Transkript kannst du erstellen, sobald die Aufnahme beendet ist.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                Text("Wird gespeichert …")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
