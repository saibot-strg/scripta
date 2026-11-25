import SwiftUI

/// Which part of a recording the detail view shows.
enum DetailPane: String, CaseIterable, Identifiable {
    case transcript, summary

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .transcript: "Transkript"
        case .summary: "Zusammenfassung"
        }
    }
}

/// The "Zusammenfassung" pane: the stored summary, the one being written,
/// or a card to start one.
struct SummaryView: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    /// The summary file is read by `RecordingDetailView` when a recording is
    /// selected; until then nothing is shown, so no empty card flashes up.
    var body: some View {
        let service = appModel.languageModels
        if let job = service.summaryJobs[recording.id] {
            SummaryProgressView(recording: recording, progress: job.progress)
        } else if let summary = service.summaries[recording.id] {
            content(summary)
        } else if service.checkedSummaryIDs.contains(recording.id) {
            SummaryEmptyCard(recording: recording)
        }
    }

    private func content(_ summary: TranscriptSummary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if summary.isOutdated(for: recording.transcript) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .foregroundStyle(.orange)
                    Text("Das Transkript wurde seitdem geändert.")
                    Spacer()
                    Button("Neu erstellen") { appModel.summarize(recording) }
                        .disabled(appModel.languageModels.summaryModel == nil)
                }
                .padding(12)
                .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
            }

            SummaryMarkdownView(markdown: summary.text)

            Divider()

            HStack(spacing: 12) {
                Text("\(summary.modelName) · \(summary.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Kopieren", systemImage: "doc.on.doc") { appModel.copySummary(of: recording) }
                Button("Neu erstellen", systemImage: "arrow.clockwise") { appModel.summarize(recording) }
                    .disabled(appModel.languageModels.summaryModel == nil)
            }
            .controlSize(.small)
        }
    }
}

/// While a summary is written: what the model is doing, then the text as it grows.
private struct SummaryProgressView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recording: Recording
    let progress: SummaryGeneration.Progress?

    var body: some View {
        if case .writing(let text) = progress, !text.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Wird geschrieben …").foregroundStyle(.secondary)
                    Spacer()
                    Button("Abbrechen") { appModel.cancelSummary(of: recording) }
                        .controlSize(.small)
                }
                SummaryMarkdownView(markdown: text)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                Text("Zusammenfassung wird erstellt …")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                Button("Abbrechen") { appModel.cancelSummary(of: recording) }
                    .controlSize(.large)
                    .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(.background.secondary, in: .rect(cornerRadius: 20))
        }
    }

    private var message: String {
        switch progress {
        case .part(let index, let count):
            String(localized: "Das Transkript ist lang und wird in Teilen gelesen: Teil \(index) von \(count).")
        case .writing, nil:
            if appModel.transcription.runningID != nil {
                String(localized: "Startet, sobald die laufende Transkription fertig ist.")
            } else {
                String(localized: "Das Sprachmodell liest das Transkript. Das dauert je nach Länge bis zu einer Minute.")
            }
        }
    }
}

/// No summary yet: start one, or say which model is needed.
private struct SummaryEmptyCard: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    var body: some View {
        let model = appModel.languageModels.summaryModel
        VStack(spacing: 14) {
            Image(systemName: "text.append")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Noch keine Zusammenfassung")
                .font(.title3.weight(.semibold))
            Group {
                if let model {
                    Text("Kurzfassung, Kernpunkte, Aufgaben und Entscheidungen – geschrieben von \(model.name), lokal auf diesem Mac.")
                } else {
                    Text("Für Zusammenfassungen brauchst du ein Sprachmodell. Lade eines in den Einstellungen unter „Erkennung“, zum Beispiel Qwen 3.5 4B (3 GB).")
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            Group {
                if model != nil {
                    Button("Zusammenfassung erstellen") { appModel.summarize(recording) }
                        .buttonStyle(.borderedProminent)
                } else {
                    SettingsLink { Text("Einstellungen öffnen") }
                }
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}
