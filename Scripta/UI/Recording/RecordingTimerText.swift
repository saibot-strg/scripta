import SwiftUI

/// Elapsed time of the running recording; the digits roll once per second.
struct RecordingTimerText: View {
    let recorder: AudioRecorder
    /// Rolling digits on every second; off for the large clock.
    var animatesDigits = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowVisible) private var isWindowVisible

    var body: some View {
        Text(Formatters.duration(TimeInterval(recorder.elapsedSeconds)))
            .monospacedDigit()
            .contentTransition(animatesDigits ? .numericText() : .identity)
            .animation(reduceMotion || !isWindowVisible || !animatesDigits ? nil : .snappy, value: recorder.elapsedSeconds)
    }
}
