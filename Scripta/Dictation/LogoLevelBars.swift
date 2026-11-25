import SwiftUI

/// The four bars of the Scripta logo, moving with the voice: at rest they
/// show the logo small, speaking raises them up to its full shape.
struct LogoLevelBars: View {
    let history: LevelHistory
    let clock: MeterClock
    var tint: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !clock.isRunning)) { _ in
            let position = clock.position(at: .now) ?? Double(history.count)
            LogoBarsShape(levels: Self.levels(in: history, at: position))
                .fill(tint)
        }
    }

    /// How far each bar (left to right) is raised, 0...1. Each bar reads the
    /// level a little later than the tall one, so the movement runs through
    /// them; peaks rise at once and fall off over about 150 ms.
    nonisolated static func levels(in history: LevelHistory, at position: Double) -> [Double] {
        LogoBarsShape.delays.map { delay in
            let newest = position - 1 - delay
            let level = (0..<4).map { step in
                interpolatedLevel(in: history, at: newest - Double(step)) * pow(0.8, Double(step))
            }.max() ?? 0
            // Room noise stays low, speech uses the whole range: from -37 dBFS
            // (after the meter's gain) to -16 dBFS, where levelled speech peaks.
            return min(max((level - 0.26) / 0.42, 0), 1)
        }
    }

    private nonisolated static func interpolatedLevel(in history: LevelHistory, at position: Double) -> Double {
        let lower = Int(position.rounded(.down))
        let fraction = position - Double(lower)
        let a = Double(history.level(at: lower) ?? 0)
        let b = Double(history.level(at: lower + 1) ?? 0)
        return a + (b - a) * fraction
    }
}

/// Four rounded bars with the logo's proportions.
struct LogoBarsShape: Shape {
    /// Heights of the logo's bars relative to the tallest one.
    static let proportions: [CGFloat] = [0.36, 1, 0.70, 0.47]
    /// Blocks each bar lags behind the newest level (the tall one first).
    static let delays: [Double] = [1.5, 0, 0.75, 2.25]
    /// Share of the logo's height the bars keep at rest.
    static let rest: CGFloat = 0.3

    /// How far each bar is raised, 0...1.
    var levels: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = CGFloat(Self.proportions.count)
        // Bars and gaps about as wide as in the logo.
        let barWidth = rect.width / (count + (count - 1) * 0.85)
        let gap = barWidth * 0.85
        for (index, proportion) in Self.proportions.enumerated() {
            let level = index < levels.count ? CGFloat(levels[index]) : 0
            let height = max(barWidth, rect.height * proportion * (Self.rest + (1 - Self.rest) * level))
            let x = rect.minX + CGFloat(index) * (barWidth + gap)
            path.addRoundedRect(
                in: CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height),
                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
            )
        }
        return path
    }
}

#Preview {
    LogoBarsShape(levels: [1, 1, 1, 1])
        .fill(.white)
        .frame(width: 23, height: 16)
        .padding()
        .background(.black)
}
