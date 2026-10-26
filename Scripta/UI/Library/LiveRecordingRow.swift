import SwiftUI

/// The running recording (or one being saved) at the top of the list, marked
/// like in Voice Memos: a red dot with the time and a light red wash.
struct LiveRecordingRow: View {
    @Environment(AppModel.self) private var appModel
    /// Increased while the row is selected in the focused list: the list then
    /// draws white text on the accent color, where red would be hard to read.
    @Environment(\.backgroundProminence) private var backgroundProminence
    let item: LiveRecording

    var body: some View {
        let recorder = appModel.recorder
        let isRunning = !item.isSaving && recorder.activeRecordingID == item.id
        let isPaused = isRunning && recorder.state == .paused
        let isHighlighted = backgroundProminence == .increased
        let tint: Color = isHighlighted ? .white : isRunning && !isPaused ? .red : .secondary

        HStack(spacing: 12) {
            SourceIcon(source: item.source)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
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
            // The selection highlight takes over while the row is selected.
            RoundedRectangle(cornerRadius: 8)
                .fill(.red.opacity(isRunning && !isHighlighted ? 0.07 : 0))
                .padding(.horizontal, -6)
                .padding(.vertical, -1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Aktuelle Aufnahme: \(item.title)"))
    }
}
