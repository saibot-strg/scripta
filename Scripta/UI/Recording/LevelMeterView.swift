import SwiftUI

/// Scrolling level bars like in Voice Memos: newest level on the right.
///
/// Each bar is one 50 ms block. `position` says where on the timeline the
/// meter is (see `MeterClock`); a fractional position shifts all bars by part
/// of a step, so the meter scrolls smoothly between blocks.
///
/// Drawn as shapes, not with `Canvas`: a canvas is redrawn on the CPU into a
/// layer of its own, which costs a lot at 60 frames per second.
struct LevelMeterView: View {
    let history: LevelHistory
    /// Block `i` sits fully at the right edge at position `i + 1`.
    let position: Double
    var tint: Color = .recording
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    @Environment(\.displayScale) private var displayScale

    /// Bars for plain levels, newest at the right edge (dictation HUD).
    init(levels: [Float], tint: Color = .recording, barWidth: CGFloat = 3, spacing: CGFloat = 2) {
        self.init(history: LevelHistory(levels), position: Double(levels.count), tint: tint, barWidth: barWidth, spacing: spacing)
    }

    init(history: LevelHistory, position: Double, tint: Color = .recording, barWidth: CGFloat = 3, spacing: CGFloat = 2) {
        self.history = history
        self.position = position
        self.tint = tint
        self.barWidth = barWidth
        self.spacing = spacing
    }

    var body: some View {
        ZStack {
            bars(.beforeStart).fill(Color.secondary.opacity(0.35))
            bars(.recorded).fill(tint)
        }
        .accessibilityHidden(true)
    }

    private func bars(_ part: LevelBars.Part) -> LevelBars {
        LevelBars(
            part: part, history: history, position: position,
            barWidth: barWidth, spacing: spacing, displayScale: displayScale
        )
    }
}

/// The bars of a `LevelMeterView` as one path.
struct LevelBars: Shape {
    enum Part {
        /// Placeholder dots for the time before the recording started.
        case beforeStart
        /// Bars of recorded blocks; blocks not arrived yet count as silence.
        case recorded
    }

    let part: Part
    let history: LevelHistory
    let position: Double
    let barWidth: CGFloat
    let spacing: CGFloat
    let displayScale: CGFloat

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        let step = barWidth + spacing
        let newest = Int(position.rounded(.down))
        let visible = Int(bounds.width / step) + 2
        for index in (newest - visible)...newest where (index < 0) == (part == .beforeStart) {
            // Right edge of the bar; snapped to pixels so bars stay crisp while moving.
            let right = bounds.maxX - CGFloat(position - Double(index + 1)) * step
            let x = ((right - barWidth) * displayScale).rounded() / displayScale
            let level = index < 0 ? 0 : CGFloat(history.level(at: index) ?? 0)
            let height = max(barWidth, level * bounds.height)
            // Bars sliding in or out at the edges are cut off.
            let bar = CGRect(x: x, y: bounds.midY - height / 2, width: barWidth, height: height)
                .intersection(bounds)
            guard !bar.isEmpty else { continue }
            let radius = min(barWidth, bar.width) / 2
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}

#Preview {
    LevelMeterView(levels: (0..<80).map { Float(abs(sin(Double($0) / 4))) })
        .frame(width: 220, height: 28)
        .padding()
}
