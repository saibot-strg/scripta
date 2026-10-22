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
    /// The speaker diarization model, used when "Sprecher unterscheiden" is on.
    private(set) var diarizerState: ModelState
    /// Progress (0...1) of the running job, by recording ID.
    private(set) var progress: [UUID: Double] = [:]
    /// Recording IDs waiting or running, in order.
    private(set) var queue: [UUID] = []
    private(set) var runningID: UUID?
    /// Number of speakers the user said a queued recording has.
    private var speakerCounts: [UUID: Int] = [:]

    private let engine: any TranscriptionEngine
    private let diarizer: (any SpeakerDiarizing)?
    /// Recognizes known people in new transcripts (if the user turned it on).
    private let voices: VoiceLibrary?
    private let library: LibraryService
    private var worker: Task<Void, Never>?
    private var currentJob: Task<[TrackKind: TrackTranscript], any Error>?
    private var preparation: Task<Void, any Error>?
    private var diarizerPreparation: Task<Void, any Error>?
    private var idleUnload: Task<Void, Never>?

    /// The loaded model takes several hundred MB; free it after this idle time.
    static let idleUnloadDelay: Duration = .seconds(300)

    /// Keeps the model in memory (dictation needs it instantly).
    var keepsModelLoaded = false {
        didSet {
            if keepsModelLoaded { idleUnload?.cancel() } else if worker == nil { scheduleIdleUnload() }
        }
    }

    /// Without a diarizer, meetings get "Ich" and "Andere" only (tests).
    init(
        library: LibraryService,
        engine: any TranscriptionEngine = ParakeetEngine(),
        diarizer: (any SpeakerDiarizing)? = nil,
        voices: VoiceLibrary? = nil
    ) {
        self.library = library
        self.engine = engine
        self.diarizer = diarizer
        self.voices = voices
        modelState = ParakeetEngine.isModelInstalled ? .installed : .notInstalled
        diarizerState = SpeakerDiarizer.isModelInstalled ? .installed : .notInstalled
    }

    var isModelInstalled: Bool { ParakeetEngine.isModelInstalled }
    var isDiarizerInstalled: Bool { SpeakerDiarizer.isModelInstalled }

    /// Speakers are told apart if a diarizer is available and the setting is on.
    private var separatesSpeakers: Bool {
        diarizer != nil && TranscriptionSettings.separatesSpeakers
    }

    /// Downloading or loading a model, or running a job.
    var isBusy: Bool {
        if runningID != nil || preparation != nil || diarizerPreparation != nil { return true }
        for state in [modelState, diarizerState] {
            switch state {
            case .downloading, .loading: return true
            default: continue
            }
        }
        return false
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
        modelState = Self.state(for: phase)
    }

    private static func state(for phase: ModelPreparation) -> ModelState {
        switch phase {
        case .downloading(let fraction): .downloading(fraction: fraction)
        case .loading: .loading
        }
    }

    /// Downloads (first run) and loads the diarization model. Safe to call repeatedly.
    func prepareDiarizer() async throws {
        guard let diarizer else { return }
        if let diarizerPreparation {
            return try await diarizerPreparation.value
        }
        if diarizerState == .ready { return }
        let task = Task { [weak self] in
            try await diarizer.prepare { phase in
                Task { @MainActor in
                    guard let self, self.diarizerState != .ready else { return }
                    self.diarizerState = Self.state(for: phase)
                }
            }
        }
        diarizerPreparation = task
        defer { diarizerPreparation = nil }
        do {
            try await task.value
            diarizerState = .ready
        } catch {
            diarizerState = .failed(message: error.localizedDescription)
            throw TranscriptionError.modelUnavailable(underlying: error)
        }
    }

    /// First launch: downloads the models in the background so the first
    /// transcription can start right away. Frees the memory again when idle.
    func installModelIfNeeded() async {
        let needsModel = !isModelInstalled
        let needsDiarizer = separatesSpeakers && !isDiarizerInstalled
        guard needsModel || needsDiarizer else { return }
        do {
            if needsModel {
                try await prepareModel()
            }
            if needsDiarizer {
                try await prepareDiarizer()
            }
            scheduleIdleUnload()
        } catch {
            Logger.transcription.error("Model download failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes the downloaded model (Settings). It is downloaded again when needed.
    func deleteModel() async {
        await engine.unload()
        try? FileManager.default.removeItem(at: ParakeetEngine.modelDirectory)
        ParakeetEngine.removeLegacyModels()
        modelState = .notInstalled
    }

    /// Deletes the diarization model (Settings). It is downloaded again when needed.
    func deleteDiarizer() async {
        await diarizer?.unload()
        try? FileManager.default.removeItem(at: SpeakerDiarizer.modelDirectory)
        diarizerState = .notInstalled
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

    /// `speakerCount`: the number of voices on the system track (meetings) or
    /// in the recording, when the user corrects a wrong separation.
    func enqueue(_ recording: Recording, speakerCount: Int? = nil) {
        guard !queue.contains(recording.id) else { return }
        speakerCounts[recording.id] = speakerCount
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
            speakerCounts[recording.id] = nil
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
            await diarizer?.unload()
            if diarizerState == .ready { diarizerState = .installed }
        }
    }

    // MARK: - Job

    /// Where an audio file comes from; decides how speakers are labeled.
    enum TrackKind: Sendable {
        case microphone
        case system
        /// A recording without separate tracks (microphone recording, import).
        case single
    }

    /// Words of one track and, if diarization ran, who spoke when.
    struct TrackTranscript: Sendable {
        var words: [WordTiming]
        var speakers: Diarization?
    }

    private struct Input {
        let url: URL
        let kind: TrackKind
    }

    /// Share of a track's progress taken by transcription when diarization
    /// follows (measured: ~7 s vs. ~15 s per hour of audio on an M5 Pro).
    /// Running both in parallel saved only ~5 % (they share the Neural
    /// Engine) at a higher memory peak, so they run one after the other.
    private static let transcriptionShare = 0.3

    /// In an online meeting only the local user speaks into the microphone, so
    /// splitting it is wasted work. It is split if the user says several people
    /// share the microphone, or if the system track is (nearly) silent: an
    /// in-person meeting recorded in meeting mode.
    nonisolated static func microphoneNeedsSpeakers(system: [WordTiming]) -> Bool {
        TranscriptionSettings.separatesRoomSpeakers || system.count < 20
    }

    private func process(_ id: UUID) async {
        guard let recording = library.recording(withID: id) else { return }
        recording.status = .running
        try? library.save()

        // Meetings: transcribe "Ich" and "Andere" separately for speaker labels.
        let inputs: [Input]
        if let microphone = library.audioURL(for: recording, role: .microphone),
           let system = library.audioURL(for: recording, role: .system) {
            // System first: whether the microphone needs diarization depends on it.
            inputs = [Input(url: system, kind: .system), Input(url: microphone, kind: .microphone)]
        } else if let primary = library.audioURL(for: recording) {
            inputs = [Input(url: primary, kind: .single)]
        } else {
            fail(recording, with: TranscriptionError.audioMissing)
            return
        }

        let engine = engine
        let diarizer = separatesSpeakers ? diarizer : nil
        let speakerCount = speakerCounts.removeValue(forKey: id)
        let job = Task {
            try await self.prepareModel()
            var tracks: [TrackKind: TrackTranscript] = [:]
            for (index, input) in inputs.enumerated() {
                try Task.checkCancellation()
                let wantsSpeakers = input.kind != .microphone
                    || Self.microphoneNeedsSpeakers(system: tracks[.system]?.words ?? [])
                let trackDiarizer = wantsSpeakers ? diarizer : nil
                let share = trackDiarizer == nil ? 1 : Self.transcriptionShare
                let report: @Sendable (Double) -> Void = { fraction in
                    let overall = (Double(index) + fraction) / Double(inputs.count)
                    Task { @MainActor in self.progress[id] = overall }
                }
                let result = try await engine.transcribe(fileURL: input.url) { report($0 * share) }
                let speakers = result.words.isEmpty
                    ? nil
                    : try await self.diarize(
                        input.url, with: trackDiarizer, speakerCount: input.kind == .microphone ? nil : speakerCount
                    ) { report(share + $0 * (1 - share)) }
                tracks[input.kind] = TrackTranscript(words: result.words, speakers: speakers)
            }
            return tracks
        }
        currentJob = job
        defer { currentJob = nil }

        do {
            let tracks = try await job.value
            // The recording may have been deleted while transcribing.
            guard let recording = library.recording(withID: id) else { return }
            let draft: DraftTranscript
            if let me = tracks[.microphone], let others = tracks[.system] {
                draft = TranscriptBuilder.meetingTranscript(
                    microphone: me.words, microphoneSpeakers: me.speakers,
                    system: others.words, systemSpeakers: others.speakers
                )
            } else if let single = tracks[.single] {
                draft = TranscriptBuilder.transcript(from: single.words, diarization: single.speakers)
            } else {
                draft = DraftTranscript(segments: [])
            }
            try store(draft, in: recording)
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

    /// Diarization is a bonus: if it fails, the transcript is still stored,
    /// just without separate speakers. Nil without a diarizer.
    private func diarize(
        _ url: URL,
        with diarizer: (any SpeakerDiarizing)?,
        speakerCount: Int?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Diarization? {
        guard let diarizer else { return nil }
        do {
            try await prepareDiarizer()
            return try await diarizer.diarize(fileURL: url, speakerCount: speakerCount, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            Logger.transcription.error("Diarization failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fail(_ recording: Recording, with error: any Error) {
        Logger.transcription.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        recording.status = .failed
        recording.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        try? library.save()
    }

    /// Replaces the recording's transcript with the new segments and names
    /// the speakers whose voices are recognized.
    private func store(_ draft: DraftTranscript, in recording: Recording) throws {
        let drafts = draft.segments
        if let old = recording.transcript {
            voices?.forget(labelIDs: old.speakers.map(\.id))
            recording.transcript = nil
            library.modelContext.delete(old)
        }
        let text = drafts.map(\.text).joined(separator: " ")
        let transcript = Transcript(
            languageCode: TranscriptBuilder.detectLanguage(of: text),
            engineIdentifier: engine.identifier
        )
        recording.transcript = transcript

        var speakers: [SpeakerKey: SpeakerLabel] = [:]
        for (index, draft) in drafts.enumerated() {
            let segment = TranscriptSegment(index: index, start: draft.start, end: draft.end, text: draft.text, words: draft.words)
            transcript.segments.append(segment)
            guard let key = draft.speaker else { continue }
            if speakers[key] == nil {
                let label = SpeakerLabel(role: key.role, number: key.number)
                transcript.speakers.append(label)
                speakers[key] = label
            }
            segment.speaker = speakers[key]
        }
        if let voices {
            let labelVoices = speakers.compactMap { key, label in
                draft.voices[key].map { embedding in
                    LabelVoice(
                        labelID: label.id,
                        embedding: embedding,
                        speechSeconds: drafts.filter { $0.speaker == key }.reduce(0) { $0 + $1.end - $1.start }
                    )
                }
            }
            for (labelID, name) in voices.recognize(labelVoices, recordingID: recording.id) {
                speakers.values.first { $0.id == labelID }?.customName = name
            }
        }
        transcript.rebuildFullText()
        recording.languageCode = transcript.languageCode
        recording.status = .done
        recording.errorMessage = nil
        try library.save()
        Logger.transcription.notice("Transcribed \(drafts.count) segments")
    }
}
