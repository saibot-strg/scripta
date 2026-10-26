import SwiftUI

/// What the dictation pill shows in each phase.
struct DictationHUDContent: View {
    let controller: DictationController
    let reduceMotion: Bool

    var body: some View {
        switch controller.phase {
        case .idle:
            EmptyView()
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            LevelMeterView(levels: controller.levels, tint: .red)
                .frame(height: 22)
        case .transcribing:
            ProgressView().controlSize(.small)
            Text("Wird erkannt …")
            Spacer(minLength: 0)
        case .finished(let result):
            Image(systemName: result.symbol)
                .foregroundStyle(result.isSuccess ? .green : .orange)
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
