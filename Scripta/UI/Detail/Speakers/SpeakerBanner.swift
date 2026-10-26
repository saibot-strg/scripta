import SwiftUI

/// Above a transcript with unnamed voices: invites to assign them.
struct SpeakerBanner: View {
    @Environment(AppModel.self) private var appModel
    let transcript: Transcript
    let action: () -> Void

    var body: some View {
        let unnamed = transcript.speakers.filter { $0.role == .diarized && $0.customName == nil }
        let guessed = transcript.speakers.filter { $0.isGuess(in: appModel.voices) }
        if !unnamed.isEmpty || !guessed.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "person.wave.2")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unnamed.isEmpty ? "\(guessed.count) Namen vermutet" : "\(unnamed.count) Stimmen ohne Namen")
                        .font(.headline)
                    Text(guessed.isEmpty
                         ? "Hör kurz rein und gib jeder Stimme einen Namen."
                         : "Vermutete Namen sind mit „?“ markiert. Hör rein und bestätige oder korrigiere sie.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Zuordnen …", action: action)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }
}
