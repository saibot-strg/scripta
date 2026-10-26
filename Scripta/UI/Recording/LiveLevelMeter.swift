import SwiftUI

/// Level bars of the running recording. Reads the levels itself, so only
/// this view redraws at the meter rate (20 times per second), not its parent.
struct LiveLevelMeter: View {
    enum Track {
        case microphone
        case system
    }

    let recorder: AudioRecorder
    var track = Track.microphone
    var tint: Color = .red
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    var body: some View {
        LevelMeterView(
            levels: track == .system ? recorder.systemLevels : recorder.levels,
            tint: tint,
            barWidth: barWidth,
            spacing: spacing
        )
    }
}
