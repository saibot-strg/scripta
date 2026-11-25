import SwiftUI

/// Detail column while a recording runs: what is being recorded, a large
/// clock, the scrolling levels and three round buttons.
struct LiveRecordingDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowVisible) private var isWindowVisible
    @AppStorage(SettingsKey.autoTranscribe) private var autoTranscribe = false
    let item: LiveRecording

    var body: some View {
        let recorder = appModel.recorder
        let isRunning = !item.isSaving && recorder.activeRecordingID == item.id
        let isPaused = isRunning && recorder.state == .paused

        VStack(spacing: 26) {
            HStack(spacing: 8) {
                if isRunning {
                    Group {
                        if isPaused {
                            Image(systemName: "pause.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        } else {
                            RecordingDot(isPulsing: !reduceMotion && isWindowVisible)
                                .foregroundStyle(.recording)
                        }
                    }
                    .frame(width: 10)
                    .accessibilityHidden(true)
                }
                Text(item.title)
                    .font(.title3.weight(.medium))
                    .lineLimit(1)
            }

            if isRunning {
                // Without the rolling digits: at this size their blur costs CPU on every second.
                RecordingTimerText(recorder: recorder, animatesDigits: false)
                    .font(.system(size: 92, weight: .ultraLight))
                    .foregroundStyle(isPaused ? .secondary : .primary)
                    .accessibilityLabel(Text(isPaused ? "Aufnahme pausiert" : "Aufnahme läuft"))

                LiveRecordingLevels(recorder: recorder, isMeeting: item.source == .meeting, isPaused: isPaused)
                    .frame(maxWidth: 680)

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
