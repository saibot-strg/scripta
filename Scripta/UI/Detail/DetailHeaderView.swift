import SwiftUI

/// Title and one line of facts at the top of the detail view. The status only
/// shows while something is open; a finished transcript speaks for itself.
struct DetailHeaderView: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recording.title)
                .font(.title.bold())
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Text(verbatim: facts)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(verbatim: spokenFacts))
                if recording.status != .done {
                    StatusBadge(status: recording.status, progress: appModel.transcription.progress[recording.id] ?? 0)
                }
            }
        }
    }

    private var language: String? {
        (recording.transcript?.languageCode ?? recording.languageCode).map(Formatters.languageName)
    }

    /// "25. Nov. 2026, 14:02 · 47 Min. · Meeting · Deutsch"
    private var facts: String {
        [
            recording.createdAt.formatted(date: .abbreviated, time: .shortened),
            Formatters.shortDuration(recording.duration),
            String(localized: recording.source.label),
            language
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var spokenFacts: String {
        [
            recording.createdAt.formatted(date: .complete, time: .shortened),
            Formatters.spokenDuration(recording.duration),
            String(localized: recording.source.label),
            language
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
