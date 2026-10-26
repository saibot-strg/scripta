import SwiftUI

/// Transcribe, transcribe again or cancel, depending on the recording's status.
struct TranscribeToolbarButton: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording
    let hasAudio: Bool

    var body: some View {
        switch recording.status {
        case .queued, .running:
            Button("Transkription abbrechen", systemImage: "xmark.circle", action: cancel)
                .help("Transkription abbrechen")
        case .done:
            Button("Erneut transkribieren", systemImage: "arrow.clockwise", action: transcribe)
                .help("Transkript neu erstellen")
                .disabled(!hasAudio)
        case .notTranscribed, .failed:
            Button("Transkribieren", systemImage: "text.bubble", action: transcribe)
                .help("Lokal mit Parakeet transkribieren")
                .disabled(!hasAudio)
        }
    }

    private func transcribe() {
        appModel.requestTranscription(of: recording)
    }

    private func cancel() {
        appModel.cancelTranscription(of: recording)
    }
}
