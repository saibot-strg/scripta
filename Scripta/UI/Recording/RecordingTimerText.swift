import SwiftUI

/// Elapsed time of the running recording; the digits roll once per second.
struct RecordingTimerText: View {
    let recorder: AudioRecorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(Formatters.duration(TimeInterval(recorder.elapsedSeconds)))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .snappy, value: recorder.elapsedSeconds)
    }
}
