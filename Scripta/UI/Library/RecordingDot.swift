import SwiftUI

/// Small round "recording" dot in the current foreground style, gently
/// fading in and out while recording (steady with Reduce Motion).
struct RecordingDot: View {
    let isPulsing: Bool

    var body: some View {
        if isPulsing {
            Circle()
                .frame(width: 7, height: 7)
                .phaseAnimator([1.0, 0.35]) { dot, opacity in
                    dot.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
        } else {
            Circle()
                .frame(width: 7, height: 7)
        }
    }
}
