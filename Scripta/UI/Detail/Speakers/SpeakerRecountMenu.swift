import SwiftUI

/// Wrong number of voices (one person split up, two merged): transcribe
/// again with the right number.
struct SpeakerRecountMenu: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording
    let hasAudio: Bool
    /// Called after the new transcription was queued (closes the sheet).
    let onRecount: () -> Void
    @State private var correctedCount: Int?

    var body: some View {
        let isMeeting = recording.source == .meeting
        Menu(isMeeting ? "Anzahl der anderen korrigieren" : "Anzahl der Personen korrigieren") {
            ForEach(1...10, id: \.self) { count in
                Button("\(count)") { correctedCount = count }
            }
        }
        .fixedSize()
        .help(isMeeting
              ? "Wie viele Personen außer dir waren zu hören? Das Transkript wird mit genau so vielen Stimmen neu erstellt."
              : "Wie viele Personen waren zu hören? Das Transkript wird mit genau so vielen Stimmen neu erstellt.")
        .disabled(!hasAudio)
        .confirmationDialog("Mit \(correctedCount ?? 0) Stimmen neu erkennen?", item: $correctedCount) { count in
            Button("Neu erkennen") {
                appModel.transcribe(recording, speakerCount: count)
                onRecount()
            }
        } message: { _ in
            Text("Das Transkript wird neu erstellt; Textkorrekturen und Namen in diesem Transkript gehen verloren. Bekannte Stimmen schlägt Scripta wieder vor.")
        }
    }
}
