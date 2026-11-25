import SwiftUI

/// Level bars of the running recording. Reads the levels itself, so only this
/// view redraws while recording, not its parent. Scrolls with the recording's
/// clock at up to 60 frames per second, stands still while paused and doesn't
/// draw at all while its window can't be seen.
struct LiveLevelMeter: View {
    enum Track {
        case microphone
        case system
    }

    let recorder: AudioRecorder
    var track = Track.microphone
    var tint: Color = .recording
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    @Environment(\.isWindowVisible) private var isWindowVisible

    var body: some View {
        if isWindowVisible {
            meter
        } else {
            // Reads nothing from the recorder, so new levels don't redraw anything.
            Color.clear
        }
    }

    private var meter: some View {
        ScrollingLevelMeter(
            history: track == .system ? recorder.systemLevels : recorder.levels,
            clock: recorder.meterClock,
            tint: tint,
            barWidth: barWidth,
            spacing: spacing
        )
    }
}
