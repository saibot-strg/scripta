import SwiftUI

/// The running recording (or one being saved) at the top of the list, marked
/// like in Voice Memos: a red dot with the time and a light red wash.
struct LiveRecordingRow: View {
    @Environment(AppModel.self) private var appModel
    let item: LiveRecording

    var body: some View {
        let recorder = appModel.recorder
        let isRunning = !item.isSaving && recorder.activeRecordingID == item.id
        let isPaused = isRunning && recorder.state == .paused
        let tint: Color = isRunning && !isPaused ? .recording : .rowDetail

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color.rowTitle)
                    .lineLimit(1)
                LiveRecordingStatusLine(isRunning: isRunning, isPaused: isPaused, tint: tint, recorder: recorder)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            LiveLevelMeter(recorder: recorder, tint: tint, barWidth: 2, spacing: 1.5)
                .frame(width: 48, height: 18)
                .opacity(isRunning ? 1 : 0)
        }
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.recording.opacity(isRunning ? 0.07 : 0))
                .padding(.horizontal, -6)
                .padding(.vertical, -1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Aktuelle Aufnahme: \(item.title)"))
    }
}
