import Foundation

/// Words recognized in one audio file, with timings.
struct EngineTranscript: Sendable {
    var words: [WordTiming]
    var duration: TimeInterval
}

/// Speech-to-text backend. Keeping this small lets other engines (e.g. a
/// Whisper variant) replace Parakeet without touching the rest of the app.
protocol TranscriptionEngine: Sendable {
    /// Stored with each transcript, e.g. "parakeet-tdt-0.6b-v3".
    var identifier: String { get }

    /// Downloads (first run) and loads the model. Progress is 0...1.
    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws

    /// Transcribes a file in any format AVFoundation can read. Runs off the
    /// main actor and honors task cancellation. Progress is 0...1.
    func transcribe(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> EngineTranscript

    /// Short audio already in memory (16 kHz mono Float32), e.g. dictation.
    /// Must not wait for a running file transcription.
    func transcribe(samples: [Float]) async throws -> EngineTranscript

    /// Frees the model's memory; the next call loads it again.
    func unload() async
}

/// Model download and loading phases.
enum ModelPreparation: Sendable, Equatable {
    case downloading(fraction: Double)
    case loading
}

enum TranscriptionError: LocalizedError {
    case modelUnavailable(underlying: any Error)
    case audioMissing
    case audioTooShort
    case engineFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            String(localized: "Das Spracherkennungsmodell konnte nicht geladen werden.")
        case .audioMissing:
            String(localized: "Die Audiodatei dieser Aufnahme fehlt.")
        case .audioTooShort:
            String(localized: "Die Aufnahme ist zu kurz für eine Transkription.")
        case .engineFailed:
            String(localized: "Die Transkription ist fehlgeschlagen.")
        }
    }

    var failureReason: String? {
        switch self {
        case .modelUnavailable(let error), .engineFailed(let error):
            error.localizedDescription
        case .audioMissing, .audioTooShort:
            nil
        }
    }
}
