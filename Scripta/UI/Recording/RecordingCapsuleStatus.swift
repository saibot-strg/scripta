import SwiftUI

/// Left part of the recording capsule: saving/starting state, or the red
/// dot, elapsed time and level meters.
struct RecordingCapsuleStatus: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recorder: AudioRecorder

    var body: some View {
        if appModel.isSavingRecording {
            Label {
                Text(appModel.savingRecordings.contains { $0.source == .meeting } ? "Meeting wird gespeichert …" : "Aufnahme wird gespeichert …")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.callout.weight(.medium))
        } else if recorder.state == .starting {
            Label {
                Text(recorder.isMeeting ? "Systemaudio wird verbunden …" : "Aufnahme startet …")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.callout.weight(.medium))
        } else {
            let isPaused = recorder.state == .paused
            HStack(spacing: 10) {
                Image(systemName: isPaused ? "pause.circle.fill" : "circle.fill")
                    .font(isPaused ? .body : .caption)
                    .foregroundStyle(isPaused ? Color.secondary : Color.red)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isPaused && !reduceMotion)
                    .frame(width: 16)

                RecordingTimerText(recorder: recorder)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 52, alignment: .leading)

                if recorder.isMeeting {
                    VStack(spacing: 3) {
                        CapsuleMeter(label: "Ich", recorder: recorder, track: .microphone, tint: isPaused ? .secondary : .red)
                        CapsuleMeter(label: "Andere", recorder: recorder, track: .system, tint: isPaused ? .secondary : .green)
                    }
                    .padding(.vertical, 6)
                } else {
                    LiveLevelMeter(recorder: recorder, tint: isPaused ? .secondary : .red)
                        .frame(height: 24)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isPaused ? "Aufnahme pausiert" : "Aufnahme läuft"))
            .accessibilityValue(Text(Formatters.spokenDuration(TimeInterval(recorder.elapsedSeconds))))
        }
    }
}
