import SwiftUI

/// "Wer spricht hier?": listen to each voice, name it, merge split voices.
struct SpeakerAssignmentSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.recognizesVoices) private var recognizesVoices = false
    let recording: Recording
    let transcript: Transcript

    @State private var speakers: [SpeakerLabel] = []
    @State private var overviews: [UUID: SpeakerOverview] = [:]
    @State private var names: [UUID: String] = [:]
    @State private var remembers: [UUID: Bool] = [:]
    @State private var excerpts = ExcerptPlayer()
    @State private var audioURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wer spricht hier?")
                    .font(.title2.weight(.semibold))
                Text("Hör kurz rein und gib jeder Stimme einen Namen. Bekommen zwei Sprecher denselben Namen, werden sie zusammengeführt.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            if !recognizesVoices {
                VoiceRecognitionOptIn(recognizesVoices: $recognizesVoices)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(speakers) { speaker in
                        SpeakerAssignmentRow(
                            speaker: speaker,
                            overview: overviews[speaker.id],
                            speakers: speakers,
                            names: $names,
                            remembers: $remembers,
                            recognizesVoices: recognizesVoices,
                            isPlaying: excerpts.playingID == speaker.id,
                            onPlay: { play(speaker) }
                        )
                        Divider()
                    }
                }
            }
            // A scroll view has no height of its own; show all rows up to a limit.
            .frame(height: min(CGFloat(speakers.count) * 104, 470))

            HStack {
                SpeakerRecountMenu(recording: recording, hasAudio: audioURL != nil, onRecount: { dismiss() })
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Fertig", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 620)
        .alert("Reinhören nicht möglich", isPresented: Bindable(excerpts).failure.isPresent, presenting: excerpts.failure) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .onAppear(perform: load)
        .onDisappear { excerpts.stop() }
    }

    private func load() {
        appModel.player.pause()
        audioURL = appModel.library.audioURL(for: recording)
        (speakers, overviews) = SpeakerOverview.make(for: transcript)
        for speaker in speakers {
            names[speaker.id] = speaker.displayName
            remembers[speaker.id] = true
        }
    }

    private func play(_ speaker: SpeakerLabel) {
        appModel.player.pause()
        excerpts.toggle(speaker.id, url: audioURL, excerpts: overviews[speaker.id]?.excerpts ?? [])
    }

    private func finish() {
        apply()
        dismiss()
    }

    /// Applies all names together, so swapping two names doesn't merge the
    /// speakers on the way.
    private func apply() {
        let assignments = speakers.compactMap { speaker -> AppModel.NameAssignment? in
            guard let name = names[speaker.id] else { return nil }
            let remember = remembers[speaker.id] ?? true
            let status = appModel.voices.statuses[speaker.id]
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let isChanged = trimmed != speaker.displayName
            // Shown as recognized or guessed and left as is: the user confirmed it.
            let confirmsRecognition = (status?.state == .automatic || status?.state == .suggested) && trimmed == status?.personName
            let forgets = !remember && status?.personID != nil
            guard isChanged || confirmsRecognition || forgets else { return nil }
            return AppModel.NameAssignment(speaker: speaker, name: trimmed, remember: remember)
        }
        appModel.assignNames(assignments, in: transcript)
    }
}
