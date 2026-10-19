import SwiftUI

/// One row in the recording list, styled like a System Settings row.
struct RecordingRow: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    var body: some View {
        HStack(spacing: 12) {
            SourceIcon(source: recording.source)

            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(Formatters.listDate(recording.createdAt))
                    Text(verbatim: "·")
                    Text(Formatters.duration(recording.duration))
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if recording.status == .done {
                // Finished is the normal case; keep the list calm.
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .help(Text(recording.status.label))
                    .accessibilityLabel(Text(recording.status.label))
            } else {
                // Compact so long German labels never truncate the title; full text in the tooltip.
                StatusBadge(status: recording.status, progress: appModel.transcription.progress[recording.id] ?? 0, compact: true)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
