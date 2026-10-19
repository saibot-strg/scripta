import Foundation
import SwiftData
import os

/// Transcription queue: runs one job at a time, keeps the UI responsive (the
/// engine works off the main actor) and writes results into the library.
@MainActor
@Observable
final class TranscriptionService {
    enum ModelState: Equatable {
        case notInstalled
        /// On disk, not loaded into memory.
        case installed
        case downloading(fraction: Double)
        case loading
        case ready
        case failed(message: String)
    }

    private(set) var modelState: ModelState
    /// Progress (0...1) of the running job, by recording ID.
    private(set) var progress: [UUID: Double] = [:]
    /// Recording IDs waiting or running, in order.
    private(set) var queue: [UUID] = []
    private(set) var runningID: UUID?

    private let engine: any TranscriptionEngine
    private let library: LibraryService
    private var worker: Task<Void, Never>?
    private var currentJob: Task<[SpeakerRole?: [SegmentDraft]], any Error>?
    private var preparation: Task<Void, any Error>?
    private var idleUnload: Task<Void, Never>?

    /// The loaded model takes several hundred MB; free it after this idle time.
    static let idleUnloadDelay: Duration = .seconds(300)

    /// Keeps the model in memory (dictation needs it instantly).
    var keepsModelLoaded = false {
        didSet {
            if keepsModelLoaded { idleUnload?.cancel() } else if worker == nil { scheduleIdleUnload() }
        }
    }

    init(library: LibraryService, engine: any TranscriptionEngine = ParakeetEngine()) {
        self.library = library
        self.engine = engine
        modelState = ParakeetEngine.isModelInstalled ? .installed : .notInstalled
    }

    var isModelInstalled: Bool { ParakeetEngine.isModelInstalled }

    /// Downloading or loading the model, or running a job.
    var isBusy: Bool {
        if runningID != nil || preparation != nil { return true }
        switch modelState {
        case .downloading, .loading: return true
        default: return false
        }
    }

    // MARK: - Model

    /// Downloads (first run) and loads the model. Safe to call repeatedly.
    func prepareModel() async throws {
        if let preparation {
            return try await preparation.value
        }
        if modelState == .ready { return }
        let engine = engine
        let task = Task { [weak self] in
            try await engine.prepare { phase in
                Task { @MainActor in self?.apply(phase) }
            }
        }
        preparation = task
        defer { preparation = nil }
        do {
            try await task.value
            modelState = .ready
        } catch {
            modelState = .failed(message: error.localizedDescription)
            throw TranscriptionError.modelUnavailable(underlying: error)
        }
    }

    private func apply(_ phase: ModelPreparation) {
        guard modelState != .ready else { return }
        switch phase {
        case .downloading(let fraction): modelState = .downloading(fraction: fraction)
        case .loading: modelState = .loading
        }
    }

    /// First launch: downloads the model in the background so the first
    /// transcription can start right away. Frees the memory again when idle.
    func installModelIfNeeded() async {
        guard !isModelInstalled else { return }
        do {
            try await prepareModel()
            scheduleIdleUnload()
        } catch {
            Logger.transcription.error("Model download failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes the downloaded model (Settings). It is downloaded again when needed.
    func deleteModel() async {
        await engine.unload()
        try? FileManager.default.removeItem(at: ParakeetEngine.modelDirectory)
        modelState = .notInstalled
    }

    // MARK: - Dictation

    /// Transcribes dictation audio and returns plain text. Runs next to a
    /// running file job instead of waiting for it.
    func dictate(samples: [Float]) async throws -> String {
        try await prepareModel()
        let result = try await engine.transcribe(samples: samples)
        return result.words.map(\.text).joined(separator: " ")
    }

    // MARK: - Queue

    func enqueue(_ recording: Recording) {
        guard !queue.contains(recording.id) else { return }
        recording.status = .queued
        recording.errorMessage = nil
        try? library.save()
        queue.append(recording.id)
        startWorkerIfNeeded()
    }

    /// Removes a recording from the queue or stops its running job.
    func cancel(_ recording: Recording) {
        if runningID == recording.id {
            currentJob?.cancel()
        } else if let index = queue.firstIndex(of: recording.id) {
            queue.remove(at: index)
            recording.status = recording.transcript == nil ? .notTranscribed : .done
            try? library.save()
        }
    }

    /// Re-queues jobs that were waiting or running when the app quit.
    func resumePendingJobs() {
        let pending = (try? library.modelContext.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for recording in pending where recording.status.isInProgress {
            enqueue(recording)
        }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        idleUnload?.cancel()
        worker = Task {
            while let id = queue.first {
                runningID = id
                await process(id)
                runningID = nil
                progress[id] = nil
                queue.removeAll { $0 == id }
            }
            worker = nil
            scheduleIdleUnload()
        }
    }

    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        guard !keepsModelLoaded else { return }
        idleUnload = Task {
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled, worker == nil else { return }
            await engine.unload()
            if modelState == .ready { modelState = .installed }
        }
    }

    // MARK: - Job

    private struct Input {
        let url: URL
        let speaker: SpeakerRole?
    }

    private func process(_ id: UUID) async {
        guard let recording = library.recording(withID: id) else { return }
        recording.status = .running
        try? library.save()

        // Meetings: transcribe "Ich" and "Andere" separately for speaker labels.
        let inputs: [Input]
        if let microphone = library.audioURL(for: recording, role: .microphone),
           let system = library.audioURL(for: recording, role: .system) {
            inputs = [Input(url: microphone, speaker: .me), Input(url: system, speaker: .others)]
        } else if let primary = library.audioURL(for: recording) {
            inputs = [Input(url: primary, speaker: nil)]
        } else {
            fail(recording, with: TranscriptionError.audioMissing)
            return
        }

        let engine = engine
        let job = Task {
            try await self.prepareModel()
            var drafts: [SpeakerRole?: [SegmentDraft]] = [:]
            for (index, input) in inputs.enumerated() {
                try Task.checkCancellation()
                let result = try await engine.transcribe(fileURL: input.url) { fraction in
                    let overall = (Double(index) + fraction) / Double(inputs.count)
                    Task { @MainActor in self.progress[id] = overall }
                }
                drafts[input.speaker] = TranscriptBuilder.segments(from: result.words, speaker: input.speaker)
            }
            return drafts
        }
        currentJob = job
        defer { currentJob = nil }

        do {
            let drafts = try await job.value
            // The recording may have been deleted while transcribing.
            guard let recording = library.recording(withID: id) else { return }
            let segments: [SegmentDraft]
            if let me = drafts[.me], let others = drafts[.others] {
                segments = TranscriptBuilder.mergeMeeting(me: me, others: others)
            } else {
                segments = drafts[nil] ?? []
            }
            try store(segments, in: recording)
        } catch {
            guard let recording = library.recording(withID: id) else { return }
            if job.isCancelled || error is CancellationError {
                recording.status = recording.transcript == nil ? .notTranscribed : .done
                try? library.save()
            } else {
                fail(recording, with: error)
            }
        }
    }

    private func fail(_ recording: Recording, with error: any Error) {
        Logger.transcription.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        recording.status = .failed
        recording.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        try? library.save()
    }

    /// Replaces the recording's transcript with the new segments.
    private func store(_ drafts: [SegmentDraft], in recording: Recording) throws {
        if let old = recording.transcript {
            recording.transcript = nil
            library.modelContext.delete(old)
        }
        let text = drafts.map(\.text).joined(separator: " ")
        let transcript = Transcript(
            languageCode: TranscriptBuilder.detectLanguage(of: text),
            engineIdentifier: engine.identifier
        )
        recording.transcript = transcript

        var speakers: [SpeakerRole: SpeakerLabel] = [:]
        for role in Set(drafts.compactMap(\.speaker)) {
            let label = SpeakerLabel(role: role)
            transcript.speakers.append(label)
            speakers[role] = label
        }
        for (index, draft) in drafts.enumerated() {
            let segment = TranscriptSegment(index: index, start: draft.start, end: draft.end, text: draft.text, words: draft.words)
            transcript.segments.append(segment)
            segment.speaker = draft.speaker.flatMap { speakers[$0] }
        }
        transcript.rebuildFullText()
        recording.languageCode = transcript.languageCode
        recording.status = .done
        recording.errorMessage = nil
        try library.save()
        Logger.transcription.notice("Transcribed \(drafts.count) segments")
    }
}
