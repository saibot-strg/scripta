import SwiftUI

/// Shown instead of (or above) the transcript while none exists, while a job
/// is queued or running, or after it failed.
struct TranscriptStatusCard: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    var body: some View {
        let status = recording.status
        let service = appModel.transcription

        VStack(spacing: 14) {
            Image(systemName: status == .notTranscribed ? "text.bubble" : status.systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(status == .notTranscribed ? Color.accentColor : status.tint)
                .symbolEffect(.variableColor.iterative, isActive: status == .running)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message(modelState: service.modelState))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if status == .running {
                if case .downloading(let fraction) = service.modelState {
                    ProgressView(value: fraction).frame(maxWidth: 280)
                } else {
                    ProgressView(value: service.progress[recording.id] ?? 0).frame(maxWidth: 280)
                }
            }

            actions(status: status)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func actions(status: TranscriptionStatus) -> some View {
        switch status {
        case .notTranscribed, .done:
            Button("Transkribieren") { appModel.transcribe(recording) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appModel.library.audioURL(for: recording) == nil)
        case .failed:
            Button("Erneut versuchen") { appModel.transcribe(recording) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appModel.library.audioURL(for: recording) == nil)
        case .queued, .running:
            Button("Abbrechen") { appModel.cancelTranscription(of: recording) }
                .controlSize(.large)
        }
    }

    private var title: LocalizedStringKey {
        switch recording.status {
        case .notTranscribed, .done: "Noch kein Transkript"
        case .queued: "In der Warteschlange"
        case .running: "Wird transkribiert …"
        case .failed: "Transkription fehlgeschlagen"
        }
    }

    private func message(modelState: TranscriptionService.ModelState) -> String {
        switch recording.status {
        case .notTranscribed, .done:
            if appModel.library.audioURL(for: recording) == nil {
                return String(localized: "Für diese Aufnahme gibt es keine Audiodatei.")
            }
            return String(localized: "Das Transkript wird lokal auf diesem Mac erstellt. Audio und Text verlassen deinen Mac nicht.")
        case .queued:
            return String(localized: "Die Transkription startet, sobald die vorherigen Aufträge fertig sind.")
        case .running:
            switch modelState {
            case .downloading(let fraction):
                return String(localized: "Das Spracherkennungsmodell wird einmalig geladen (ca. 640 MB) … \(fraction.formatted(.percent.precision(.fractionLength(0))))")
            case .loading:
                return String(localized: "Das Spracherkennungsmodell wird vorbereitet …")
            default:
                let fraction = appModel.transcription.progress[recording.id] ?? 0
                return String(localized: "\(fraction.formatted(.percent.precision(.fractionLength(0)))) – du kannst die App währenddessen normal weiter benutzen.")
            }
        case .failed:
            return recording.errorMessage ?? String(localized: "Unbekannter Fehler.")
        }
    }
}
