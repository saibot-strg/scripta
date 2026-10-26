import SwiftUI

/// "● 0:12 · Aufnahme läuft", "❚❚ 0:12 · Pausiert" or "Wird gespeichert …".
struct LiveRecordingStatusLine: View {
    let isRunning: Bool
    let isPaused: Bool
    let tint: Color
    let recorder: AudioRecorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isRunning {
            HStack(spacing: 5) {
                Group {
                    if isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8, weight: .bold))
                    } else {
                        RecordingDot(isPulsing: !reduceMotion)
                    }
                }
                .frame(width: 9)
                .accessibilityHidden(true)
                RecordingTimerText(recorder: recorder)
                Text(verbatim: "·")
                Text(isPaused ? "Pausiert" : "Aufnahme läuft")
            }
            .foregroundStyle(tint)
        } else {
            Label {
                Text("Wird gespeichert …")
            } icon: {
                ProgressView().controlSize(.mini)
            }
            .foregroundStyle(tint)
        }
    }
}
