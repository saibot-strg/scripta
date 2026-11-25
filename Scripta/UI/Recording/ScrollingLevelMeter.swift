import SwiftUI

/// Level bars that scroll smoothly with a `MeterClock`, at up to 60 frames
/// per second, and stand still while the clock is paused.
struct ScrollingLevelMeter: View {
    let history: LevelHistory
    let clock: MeterClock
    var tint: Color = .recording
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !clock.isRunning)) { _ in
            LevelMeterView(
                history: history,
                position: clock.position(at: .now) ?? Double(history.count),
                tint: tint,
                barWidth: barWidth,
                spacing: spacing
            )
        }
    }
}
