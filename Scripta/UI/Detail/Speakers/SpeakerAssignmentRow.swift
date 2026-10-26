import SwiftUI

/// One voice in the assignment sheet: name field, quote, share, listen.
struct SpeakerAssignmentRow: View {
    @Environment(AppModel.self) private var appModel
    let speaker: SpeakerLabel
    let overview: SpeakerOverview?
    let speakers: [SpeakerLabel]
    @Binding var names: [UUID: String]
    @Binding var remembers: [UUID: Bool]
    let recognizesVoices: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        let status = appModel.voices.statuses[speaker.id]
        let name = names[speaker.id] ?? speaker.displayName

        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(speaker.tint)
                .frame(width: 10, height: 10)
                .padding(.top, 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(speaker.defaultName, text: $names[speaker.id, fallback: speaker.displayName])
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        // "Jul" offers "Julian Zeder" instead of creating a second person.
                        .textInputSuggestions {
                            ForEach(completions(for: name)) { person in
                                Text(person.name)
                                    .textInputCompletion(person.name)
                            }
                        }
                    SpeakerChoicesMenu(speaker: speaker, speakers: speakers, names: $names)
                    if let suggested = status?.personName, status?.state == .suggested, name != suggested {
                        Button("\(suggested)?") { names[speaker.id] = suggested }
                            .help("Klingt nach \(suggested) – klicken zum Übernehmen")
                    }
                    if status?.state == .suggested, name == status?.personName {
                        Label("Vermutet", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if status?.state == .automatic {
                        Label("Erkannt", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let quote = overview?.quote {
                    Text("„\(quote)“")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 16) {
                    Text("\(overview?.share ?? 0, format: .percent.precision(.fractionLength(0))) der Redezeit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if recognizesVoices, status != nil {
                        Toggle("Stimme merken", isOn: $remembers[speaker.id, fallback: true])
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .help("Aus: nur hier benennen, z. B. für Gäste")
                    }
                }
            }

            Spacer(minLength: 0)

            Button(isPlaying ? "Stopp" : "Reinhören", systemImage: isPlaying ? "stop.fill" : "play.fill", action: onPlay)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(overview?.excerpts.isEmpty ?? true)
                .help("Reinhören (jeder Klick spielt eine andere Stelle)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Known people whose name contains what was typed (not yet complete).
    private func completions(for text: String) -> [PersonSummary] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        return appModel.voices.people.filter {
            $0.name.localizedStandardContains(typed) && $0.name.localizedCaseInsensitiveCompare(typed) != .orderedSame
        }
    }
}
