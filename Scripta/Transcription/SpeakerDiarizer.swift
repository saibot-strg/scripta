import Foundation
import FluidAudio
import os

/// One stretch of speech by one speaker.
struct SpeakerTurn: Sendable, Equatable {
    /// 1-based, numbered in order of first appearance.
    var speaker: Int
    var start: TimeInterval
    var end: TimeInterval
}

/// Who spoke when in one audio file.
struct Diarization: Sendable {
    var turns: [SpeakerTurn]
    /// Voice fingerprint per speaker (256-d, L2-normalized), used later to
    /// recognize people across recordings.
    var embeddings: [Int: [Float]] = [:]

    var speakers: [Int] { Array(Set(turns.map(\.speaker))).sorted() }

    func speechDuration(of speaker: Int) -> TimeInterval {
        turns.filter { $0.speaker == speaker }.reduce(0) { $0 + $1.end - $1.start }
    }
}

/// Speaker diarization backend; a protocol so tests can use canned results.
protocol SpeakerDiarizing: Sendable {
    /// Downloads (first run) and loads the models.
    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws

    /// Finds the speakers in a file in any format AVFoundation can read,
    /// exactly `speakerCount` of them if given. Progress is 0...1.
    func diarize(fileURL: URL, speakerCount: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization

    /// Frees the models' memory; the next call loads them again.
    func unload() async
}

extension SpeakerDiarizing {
    func diarize(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization {
        try await diarize(fileURL: fileURL, speakerCount: nil, progress: progress)
    }
}

/// pyannote community-1 (segmentation, WeSpeaker embeddings, VBx clustering)
/// through FluidAudio's offline pipeline: CoreML, fully offline once the
/// models (~30 MB) are downloaded. Reads long files memory-mapped.
actor SpeakerDiarizer: SpeakerDiarizing {
    private var models: OfflineDiarizerModels?

    nonisolated static var modelDirectory: URL {
        OfflineDiarizerModels.defaultModelsDirectory()
            .appending(path: Repo.diarizer.folderName, directoryHint: .isDirectory)
    }

    /// True if all model files are on disk (no network needed).
    nonisolated static var isModelInstalled: Bool {
        ModelNames.OfflineDiarizer.requiredModels.allSatisfy { name in
            FileManager.default.fileExists(atPath: modelDirectory.appending(path: name).path(percentEncoded: false))
        }
    }

    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        guard models == nil else { return }
        // Neural Engine and CPU only: FluidAudio's default (.all) also loads
        // the GPU, which makes the Mac hot for little gain.
        models = try await OfflineDiarizerModels.load(
            configuration: MLModelConfigurationUtils.defaultConfiguration(computeUnits: .cpuAndNeuralEngine),
            progressHandler: { update in
                switch update.phase {
                case .listing, .downloading:
                    progress(.downloading(fraction: update.fractionCompleted))
                case .compiling:
                    progress(.loading)
                }
            }
        )
        Logger.transcription.notice("Speaker diarization ready")
    }

    func diarize(fileURL: URL, speakerCount: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization {
        if models == nil {
            try await prepare { _ in }
        }
        guard let models else { throw TranscriptionError.modelUnavailable(underlying: CancellationError()) }
        // A fresh manager per file: it is cheap (the models are shared) and
        // keeps the non-Sendable manager out of the actor's state.
        let config = speakerCount.map { OfflineDiarizerConfig.default.withSpeakers(exactly: $0) } ?? .default
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)
        let result = try await manager.process(fileURL) { done, total in
            progress(Double(done) / Double(max(total, 1)))
        }
        progress(1)
        return Self.diarization(from: result)
    }

    func unload() {
        models = nil
    }

    /// Renumbers FluidAudio's speaker IDs ("S1", "S2", …) by first appearance.
    static func diarization(from result: DiarizationResult) -> Diarization {
        let segments = result.segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        var numbers: [String: Int] = [:]
        var turns: [SpeakerTurn] = []
        for segment in segments where segment.endTimeSeconds > segment.startTimeSeconds {
            let number = numbers[segment.speakerId] ?? {
                let next = numbers.count + 1
                numbers[segment.speakerId] = next
                return next
            }()
            turns.append(SpeakerTurn(
                speaker: number,
                start: TimeInterval(segment.startTimeSeconds),
                end: TimeInterval(segment.endTimeSeconds)
            ))
        }
        var embeddings: [Int: [Float]] = [:]
        for (id, embedding) in result.speakerDatabase ?? [:] {
            if let number = numbers[id] { embeddings[number] = embedding }
        }
        return Diarization(turns: turns, embeddings: embeddings)
    }
}
