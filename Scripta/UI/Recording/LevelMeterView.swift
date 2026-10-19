import SwiftUI

/// Scrolling level bars like in Voice Memos: newest level on the right.
struct LevelMeterView: View {
    let levels: [Float]
    var tint: Color = .red
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let step = barWidth + spacing
            let slots = max(Int((size.width + spacing) / step), 1)
            let recent = Array(levels.suffix(slots))
            let empty = slots - recent.count

            for slot in 0..<slots {
                let level = slot < empty ? 0 : CGFloat(recent[slot - empty])
                let height = max(barWidth, level * size.height)
                let rect = CGRect(
                    x: CGFloat(slot) * step,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let style: Color = slot < empty ? .secondary.opacity(0.35) : tint
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(style))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    LevelMeterView(levels: (0..<80).map { Float(abs(sin(Double($0) / 4))) })
        .frame(width: 220, height: 28)
        .padding()
}
