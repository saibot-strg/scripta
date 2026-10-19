import SwiftUI

/// Capsule showing the transcription status of a recording.
struct StatusBadge: View {
    let status: TranscriptionStatus
    var progress: Double = 0
    /// Icon only (plus percentage while running), for narrow list rows.
    var compact = false

    var body: some View {
        Label {
            if status == .running, progress > 0 {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            } else if !compact {
                Text(status.label)
            }
        } icon: {
            Image(systemName: status.systemImage)
                .symbolEffect(.variableColor.iterative, isActive: status == .running)
        }
        .font(.caption.weight(.medium))
        .labelStyle(.titleAndIcon)
        .help(Text(status.label))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(status.tint)
        .background(status.tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.label))
    }
}

extension TranscriptionStatus {
    var tint: Color {
        switch self {
        case .notTranscribed: .secondary
        case .queued: .orange
        case .running: .blue
        case .done: .green
        case .failed: .red
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(TranscriptionStatus.allCases, id: \.self) { StatusBadge(status: $0, progress: 0.42) }
    }
    .padding()
}
