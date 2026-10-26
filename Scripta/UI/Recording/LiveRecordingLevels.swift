import SwiftUI

/// One meter for a recording, two labelled ones ("Ich", "Andere") for a meeting.
struct LiveRecordingLevels: View {
    let recorder: AudioRecorder
    let isMeeting: Bool
    let isPaused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if isMeeting {
                LabeledLevelMeter(label: "Ich", recorder: recorder, track: .microphone, tint: isPaused ? .secondary : .red)
                LabeledLevelMeter(label: "Andere", recorder: recorder, track: .system, tint: isPaused ? .secondary : .green)
            } else {
                LiveLevelMeter(recorder: recorder, tint: isPaused ? .secondary : .red)
                    .frame(height: 40)
            }
        }
        .accessibilityHidden(true)
    }
}
