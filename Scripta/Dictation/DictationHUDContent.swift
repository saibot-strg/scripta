import SwiftUI

/// What the dictation pill shows in each phase: dot and bars while speaking,
/// the bars as a calm blue wave while recognizing, a checkmark when inserted,
/// text only when something needs attention.
struct DictationHUDContent: View {
    let controller: DictationController
    let reduceMotion: Bool

    var body: some View {
        switch controller.phase {
        case .idle:
            EmptyView()
        case .recording:
            RecordingDot(isPulsing: !reduceMotion)
                .foregroundStyle(.recording)
            LogoLevelBars(history: controller.levels, clock: controller.meterClock)
                .frame(width: 24, height: 16)
        case .transcribing:
            RecognizingWave(reduceMotion: reduceMotion)
                .frame(width: 24, height: 16)
        case .finished(let result) where result.isSuccess:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.success)
        case .finished(let result):
            Image(systemName: result.symbol)
                .foregroundStyle(.orange)
            Text(result.message)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}

/// The logo's bars rising and falling calmly while the dictation is
/// recognized (usually a fraction of a second).
private struct RecognizingWave: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            LogoBarsShape(levels: (0..<4).map { 0.45 + 0.35 * sin(time * 6 - Double($0) * 0.9) })
                .fill(Color.brandSky)
        }
    }
}
