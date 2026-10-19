import SwiftUI

/// Title, date and metadata chips at the top of the detail view.
struct DetailHeaderView: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SourceIcon(source: recording.source, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(recording.createdAt.formatted(date: .complete, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                MetadataChip(systemImage: "clock") {
                    Text(Formatters.duration(recording.duration)).monospacedDigit()
                }
                .accessibilityLabel(Text("Dauer \(Formatters.spokenDuration(recording.duration))"))

                MetadataChip(systemImage: recording.source.systemImage) {
                    Text(recording.source.label)
                }

                if let code = recording.transcript?.languageCode ?? recording.languageCode {
                    MetadataChip(systemImage: "globe") {
                        Text(Formatters.languageName(code))
                    }
                }

                StatusBadge(status: recording.status, progress: appModel.transcription.progress[recording.id] ?? 0)
            }
        }
    }
}

/// Small rounded label for a single piece of metadata.
struct MetadataChip<Content: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        Label {
            content
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.fill.tertiary, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
