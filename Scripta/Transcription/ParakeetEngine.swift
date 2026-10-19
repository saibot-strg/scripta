import Foundation
import FluidAudio
import os

/// Parakeet Ultra (multilingual, 25 European languages) through FluidAudio:
/// CoreML on the Apple Neural Engine, fully offline once the model is
/// downloaded. Ultra is moondream's post-training of NVIDIA Parakeet TDT 0.6B
/// v3: same architecture and speed, lower error rate in every language.
/// Long files are read from disk in 15 s windows, so memory stays flat even
/// for hour-long recordings.
actor ParakeetEngine: TranscriptionEngine {
    nonisolated let identifier = "parakeet-ultra"

    /// Ultra ships a single int8 encoder (~630 MB in total), so there is no
    /// encoder precision to choose.
    static let version: AsrModelVersion = .ultra
    /// Models of earlier Scripta versions, removed once Ultra is ready.
    static let legacyVersions: [AsrModelVersion] = [.v3]

    private var manager: AsrManager?
    /// Separate manager for dictation, sharing the loaded models: it can run
    /// while a long file is being transcribed (CoreML models are shareable).
    private var dictationManager: AsrManager?

    /// Where the model lives (inside the app container).
    nonisolated static var modelDirectory: URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    /// True if all model files are on disk (no network needed).
    nonisolated static var isModelInstalled: Bool {
        AsrModels.modelsExist(at: modelDirectory, version: version)
    }

    /// Deletes models of earlier versions that are still on disk.
    nonisolated static func removeLegacyModels() {
        for legacy in legacyVersions {
            let directory = AsrModels.defaultCacheDirectory(for: legacy)
            guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { continue }
            do {
                try FileManager.default.removeItem(at: directory)
                Logger.transcription.notice("Removed legacy model \(directory.lastPathComponent, privacy: .public)")
            } catch {
                Logger.transcription.error("Could not remove legacy model: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        guard manager == nil else { return }
        let wasInstalled = Self.isModelInstalled
        let models = try await AsrModels.downloadAndLoad(
            version: Self.version,
            progressHandler: { update in
                switch update.phase {
                case .listing, .downloading:
                    progress(.downloading(fraction: update.fractionCompleted))
                case .compiling:
                    progress(.loading)
                }
            }
        )
        progress(.loading)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let dictationManager = AsrManager(config: .default)
        try await dictationManager.loadModels(models)
        self.manager = manager
        self.dictationManager = dictationManager
        // The first inference is noticeably slower; do it now, not on the first dictation.
        var warmUpState = try TdtDecoderState()
        _ = try? await dictationManager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &warmUpState, language: nil)
        Logger.transcription.notice("Parakeet ready (downloaded now: \(!wasInstalled, privacy: .public))")
        // Only now: if the download had failed, the old model would still be there.
        Self.removeLegacyModels()
    }

    func transcribe(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> EngineTranscript {
        if manager == nil {
            try await prepare { _ in }
        }
        guard let manager else { throw TranscriptionError.modelUnavailable(underlying: CancellationError()) }

        // Subscribe before transcribing: FluidAudio reports progress for files over 15 s.
        let updates = await manager.transcriptionProgressStream
        let progressTask = Task {
            for try await value in updates {
                progress(value)
            }
        }
        defer { progressTask.cancel() }

        var decoderState = try TdtDecoderState()
        let result: ASRResult
        do {
            result = try await manager.transcribe(fileURL, decoderState: &decoderState, language: nil)
        } catch ASRError.invalidAudioData {
            throw TranscriptionError.audioTooShort
        }
        progress(1)
        return EngineTranscript(words: Self.words(from: result.tokenTimings ?? []), duration: result.duration)
    }

    func transcribe(samples: [Float]) async throws -> EngineTranscript {
        if dictationManager == nil {
            try await prepare { _ in }
        }
        guard let dictationManager else { throw TranscriptionError.modelUnavailable(underlying: CancellationError()) }
        // Parakeet needs at least 0.3 s.
        guard samples.count >= 4_800 else { throw TranscriptionError.audioTooShort }
        var decoderState = try TdtDecoderState()
        let result = try await dictationManager.transcribe(samples, decoderState: &decoderState, language: nil)
        return EngineTranscript(words: Self.words(from: result.tokenTimings ?? []), duration: result.duration)
    }

    func unload() {
        manager = nil
        dictationManager = nil
    }

    /// Joins sub-word tokens into words. A token starting with "▁" (or a
    /// space) begins a new word; confidence is the mean over its tokens.
    static func words(from tokens: [TokenTiming]) -> [WordTiming] {
        var words: [WordTiming] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        var confidences: [Float] = []

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Float(confidences.count)
                words.append(WordTiming(text: trimmed, start: start, end: end, confidence: confidence))
            }
            text = ""
            confidences = []
        }

        for token in tokens {
            let piece = token.token
            guard !piece.isEmpty, piece != "<blank>", piece != "<pad>" else { continue }
            let startsWord = piece.hasPrefix("▁") || piece.hasPrefix(" ")
            if startsWord || text.isEmpty {
                flush()
                text = String(piece.drop { $0 == "▁" || $0 == " " })
                start = token.startTime
            } else {
                text += piece
            }
            end = token.endTime
            confidences.append(token.confidence)
        }
        flush()
        return words
    }
}
