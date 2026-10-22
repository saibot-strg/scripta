import Foundation
import FluidAudio
import SwiftData
import Synchronization
import Testing
@testable import Scripta

// MARK: - Segmentation and merging

@Suite("Transcript building")
struct TranscriptBuilderTests {
    private func words(_ text: String, start: TimeInterval = 0, step: TimeInterval = 0.4) -> [Scripta.WordTiming] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + Double(index) * step
            return Scripta.WordTiming(text: String(word), start: begin, end: begin + step * 0.8, confidence: 0.9)
        }
    }

    @Test("Sentences become segments")
    func sentences() {
        let segments = TranscriptBuilder.segments(from: words("Hallo zusammen. Wie geht es euch? Gut!"))
        #expect(segments.map(\.text) == ["Hallo zusammen.", "Wie geht es euch?", "Gut!"])
        #expect(segments[1].start == 0.8)
    }

    @Test("Long pauses split segments, even without punctuation")
    func pauses() {
        let first = words("erster Gedanke ohne Punkt")
        let second = words("zweiter Gedanke", start: 5)
        let segments = TranscriptBuilder.segments(from: first + second)
        #expect(segments.count == 2)
        #expect(segments[1].text == "zweiter Gedanke")
    }

    @Test("Monologues without punctuation are cut at the maximum duration")
    func maxDuration() {
        let long = words(Array(repeating: "wort", count: 100).joined(separator: " "))
        let segments = TranscriptBuilder.segments(from: long, maxDuration: 10)
        #expect(segments.count >= 4)
        #expect(segments.allSatisfy { $0.end - $0.start <= 10 })
        #expect(segments.flatMap(\.words).count == 100)
    }

    @Test("Sub-word tokens are joined into words with timings and confidence")
    func tokenJoining() {
        let tokens = [
            TokenTiming(token: "▁Gu", tokenId: 1, startTime: 0.0, endTime: 0.2, confidence: 0.8),
            TokenTiming(token: "ten", tokenId: 2, startTime: 0.2, endTime: 0.4, confidence: 1.0),
            TokenTiming(token: "▁Mor", tokenId: 3, startTime: 0.5, endTime: 0.7, confidence: 0.9),
            TokenTiming(token: "gen", tokenId: 4, startTime: 0.7, endTime: 0.9, confidence: 0.9),
            TokenTiming(token: ".", tokenId: 5, startTime: 0.9, endTime: 1.0, confidence: 0.9),
            TokenTiming(token: "<blank>", tokenId: 0, startTime: 1.0, endTime: 1.1, confidence: 0.1),
        ]
        let result = ParakeetEngine.words(from: tokens)
        #expect(result.map(\.text) == ["Guten", "Morgen."])
        #expect(result[0].start == 0 && result[0].end == 0.4)
        #expect(abs((result[0].confidence ?? 0) - 0.9) < 0.001)
        #expect(result[1].end == 1.0)
    }

    @Test("Meeting merge sorts by time and drops speaker echo on the microphone")
    func meetingMerge() {
        let others = [SegmentDraft(start: 1, end: 3, words: words("Wie lange brauchst du?", start: 1), speaker: .others)]
        let me = [
            // Picked up from the speakers while "Andere" talked: echo.
            SegmentDraft(start: 1.1, end: 3, words: words("wie lange brauchst du", start: 1.1), speaker: .me),
            SegmentDraft(start: 3.5, end: 5, words: words("Bis Donnerstag.", start: 3.5), speaker: .me),
        ]
        let merged = TranscriptBuilder.mergeMeeting(me: me, others: others)
        #expect(merged.map(\.speaker) == [.others, .me])
        #expect(merged.last?.text == "Bis Donnerstag.")
    }

    @Test("Overlapping speech with different words is not treated as echo")
    func overlappingSpeech() {
        let other = SegmentDraft(start: 0, end: 2, words: words("Das Budget ist knapp"), speaker: .others)
        let mine = SegmentDraft(start: 0.5, end: 2, words: words("Ja genau so sehe ich das", start: 0.5), speaker: .me)
        #expect(!TranscriptBuilder.isEcho(mine, of: other))
    }

    @Test("Words go to the speaker turn they overlap most, else to the nearest one")
    func wordSpeakers() {
        let turns = [SpeakerTurn(speaker: 1, start: 0, end: 1.0), SpeakerTurn(speaker: 2, start: 1.1, end: 3)]
        let spoken = [
            Scripta.WordTiming(text: "a", start: 0.1, end: 0.4),
            Scripta.WordTiming(text: "b", start: 0.7, end: 1.2), // mostly 1
            Scripta.WordTiming(text: "c", start: 0.9, end: 1.5), // mostly 2
            Scripta.WordTiming(text: "d", start: 4.0, end: 4.2), // after all turns: nearest is 2
        ]
        #expect(TranscriptBuilder.speakers(of: spoken, in: turns) == [1, 1, 2, 2])
        #expect(TranscriptBuilder.speakers(of: spoken, in: []) == [nil, nil, nil, nil])
    }

    @Test("A change of speaker ends the segment")
    func speakerChange() {
        let spoken = words("Ja genau das machen wir so")
        let keys: [SpeakerKey?] = [.diarized(1), .diarized(1), .diarized(2), .diarized(2), .diarized(2), .diarized(1)]
        let segments = TranscriptBuilder.segments(from: spoken, speakers: keys)
        #expect(segments.map(\.text) == ["Ja genau", "das machen wir", "so"])
        #expect(segments.map(\.speaker) == [.diarized(1), .diarized(2), .diarized(1)])
    }

    @Test("Single recordings get numbered speakers only with more than one voice")
    func singleRecordingSpeakers() {
        let spoken = words("Hallo zusammen. Hallo Anna.") // 4 words, 0 to 1.5 s
        let one = Diarization(turns: [SpeakerTurn(speaker: 1, start: 0, end: 2)])
        #expect(TranscriptBuilder.segments(from: spoken, diarization: one).allSatisfy { $0.speaker == nil })
        #expect(TranscriptBuilder.segments(from: spoken, diarization: nil).allSatisfy { $0.speaker == nil })

        // Diarization numbers may differ from first appearance in the words.
        let two = Diarization(turns: [SpeakerTurn(speaker: 2, start: 0, end: 0.75), SpeakerTurn(speaker: 1, start: 0.75, end: 2)])
        let segments = TranscriptBuilder.segments(from: spoken, diarization: two)
        #expect(segments.map(\.text) == ["Hallo zusammen.", "Hallo Anna."])
        #expect(segments.map(\.speaker) == [.diarized(1), .diarized(2)])
    }

    @Test("Meetings: remote voices are numbered, the microphone stays 'Ich'")
    func meetingSpeakers() {
        let system = words("Wie weit seid ihr? Fast fertig.") // 0 to 2.3 s
        let systemSpeakers = Diarization(turns: [
            SpeakerTurn(speaker: 1, start: 0, end: 1.5),
            SpeakerTurn(speaker: 2, start: 1.55, end: 2.5),
        ])
        let microphone = words("Dann bis Freitag.", start: 4)
        let segments = TranscriptBuilder.meetingSegments(
            microphone: microphone, microphoneSpeakers: Diarization(turns: [SpeakerTurn(speaker: 1, start: 4, end: 5.5)]),
            system: system, systemSpeakers: systemSpeakers
        )
        #expect(segments.map(\.speaker) == [.diarized(1), .diarized(2), .me])

        // Without diarization the tracks keep "Andere" and "Ich".
        let plain = TranscriptBuilder.meetingSegments(microphone: microphone, microphoneSpeakers: nil, system: system, systemSpeakers: nil)
        #expect(Set(plain.compactMap(\.speaker)) == [.others, .me])
    }

    @Test("Meetings: a person in the room gets a number, short extra voices stay 'Ich'")
    func roomSpeakers() {
        // Microphone: the local user (12 s), a colleague in the room (10 s) and a
        // 1 s split-off of another voice.
        let user = words(Array(repeating: "ich", count: 30).joined(separator: " "), start: 0)
        let colleague = words(Array(repeating: "kollege", count: 25).joined(separator: " "), start: 20)
        let blip = words("hm ja", start: 40)
        let microphoneSpeakers = Diarization(turns: [
            SpeakerTurn(speaker: 1, start: 0, end: 12),
            SpeakerTurn(speaker: 2, start: 20, end: 30),
            SpeakerTurn(speaker: 3, start: 40, end: 41),
        ])
        let system = words("Klingt gut.", start: 50)
        let segments = TranscriptBuilder.meetingSegments(
            microphone: user + colleague + blip, microphoneSpeakers: microphoneSpeakers,
            system: system, systemSpeakers: Diarization(turns: [SpeakerTurn(speaker: 1, start: 50, end: 51)])
        )
        let speakerOfWord = segments.flatMap { segment in segment.words.map { ($0.text, segment.speaker) } }
        #expect(speakerOfWord.filter { $0.0 == "ich" }.allSatisfy { $0.1 == .me })
        #expect(speakerOfWord.filter { $0.0 == "kollege" }.allSatisfy { $0.1 == .diarized(1) })
        #expect(speakerOfWord.filter { $0.0 == "hm" || $0.0 == "ja" }.allSatisfy { $0.1 == .me })
        #expect(segments.last?.speaker == .diarized(2)) // remote, numbered by first appearance
    }

    @Test("Language detection")
    func language() {
        #expect(TranscriptBuilder.detectLanguage(of: "Wir besprechen heute das Budget für das nächste Quartal.") == "de")
        #expect(TranscriptBuilder.detectLanguage(of: "We review the product roadmap for the next quarter today.") == "en")
    }
}

// MARK: - Queue with a fake engine

/// Returns canned words per file name; can be slowed down to test cancelling.
private final class FakeEngine: TranscriptionEngine {
    let identifier = "fake"
    let delay: Duration
    let fails: Bool

    init(delay: Duration = .zero, fails: Bool = false) {
        self.delay = delay
        self.fails = fails
    }

    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws {}

    func transcribe(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> EngineTranscript {
        try await Task.sleep(for: delay)
        if fails { throw TranscriptionError.audioTooShort }
        progress(1)
        let text = fileURL.lastPathComponent.hasPrefix("system") ? "Hallo von den anderen." : "Hallo, hier spreche ich."
        let offset: TimeInterval = fileURL.lastPathComponent.hasPrefix("system") ? 0 : 3
        let words = text.split(separator: " ").enumerated().map { index, word in
            let start = offset + Double(index) * 0.5
            return Scripta.WordTiming(text: String(word), start: start, end: start + 0.4, confidence: 1)
        }
        return EngineTranscript(words: words, duration: 5)
    }

    func transcribe(samples: [Float]) async throws -> EngineTranscript {
        EngineTranscript(words: [Scripta.WordTiming(text: "Diktat.", start: 0, end: 0.5, confidence: 1)], duration: 1)
    }

    func unload() async {}
}

/// Splits the system track into two voices and finds one voice on the microphone.
private final class FakeDiarizer: SpeakerDiarizing {
    let fails: Bool
    /// Requested speaker count per file name.
    let requests = Mutex<[String: Int?]>([:])

    init(fails: Bool = false) {
        self.fails = fails
    }

    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws {}

    func diarize(fileURL: URL, speakerCount: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization {
        requests.withLock { $0[fileURL.deletingPathExtension().lastPathComponent] = speakerCount }
        if fails { throw TranscriptionError.audioTooShort }
        progress(1)
        if fileURL.lastPathComponent.hasPrefix("system") {
            // FakeEngine: "Hallo von den anderen." at 0, 0.5, 1.0, 1.5 s.
            return Diarization(turns: [SpeakerTurn(speaker: 1, start: 0, end: 0.95), SpeakerTurn(speaker: 2, start: 0.95, end: 2)])
        }
        return Diarization(turns: [SpeakerTurn(speaker: 1, start: 0, end: 5)])
    }

    func unload() async {}
}

@MainActor
@Suite("Transcription queue")
struct TranscriptionQueueTests {
    let root = TestAudio.temporaryDirectory()
    let container: ModelContainer

    init() throws {
        container = try TestStore.makeContainer()
    }

    private var library: LibraryService {
        LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: root))
    }

    /// A recording with real (tone) audio files on disk.
    private func makeRecording(meeting: Bool) throws -> Recording {
        let id = UUID()
        let manifest = meeting
            ? RecordingManifest(id: id, title: "Meeting", createdAt: .now, source: .meeting, fileName: CaptureFormat.mixFileName,
                                microphoneFileName: CaptureFormat.microphoneFileName, systemFileName: CaptureFormat.systemFileName)
            : RecordingManifest(id: id, title: "Notiz", createdAt: .now, source: .microphone, fileName: CaptureFormat.fileName)
        let storage = RecordingStorage(rootURL: root)
        try storage.makeFolder(for: id)
        for name in Set([manifest.fileName] + manifest.capturedFileNames) {
            let sink = try AudioFileSink(fileURL: storage.fileURL(for: id, fileName: name))
            TestAudio.feed(sink, sampleRate: 48_000, channels: 1, duration: 1)
            sink.finish()
        }
        return try library.addRecording(manifest: manifest, duration: 1)
    }

    private func waitUntilIdle(_ service: TranscriptionService) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (!service.queue.isEmpty || service.runningID != nil), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("A queued recording gets a transcript and status 'done'")
    func transcribeSingle() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TranscriptionService(library: library, engine: FakeEngine())
        let recording = try makeRecording(meeting: false)

        service.enqueue(recording)
        #expect(recording.status == .queued)
        try await waitUntilIdle(service)

        #expect(recording.status == .done)
        let transcript = try #require(recording.transcript)
        #expect(transcript.engineIdentifier == "fake")
        #expect(transcript.fullText.contains("hier spreche ich"))
        #expect(transcript.speakers.isEmpty)
        #expect(recording.matches(searchText: "spreche"))
    }

    @Test("Meetings are transcribed per track and labeled 'Ich' and 'Andere'")
    func transcribeMeeting() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TranscriptionService(library: library, engine: FakeEngine())
        let recording = try makeRecording(meeting: true)

        service.enqueue(recording)
        try await waitUntilIdle(service)

        let transcript = try #require(recording.transcript)
        #expect(Set(transcript.speakers.map(\.role)) == [.me, .others])
        #expect(transcript.hasSpeakers)
        let ordered = transcript.orderedSegments
        #expect(ordered.first?.speaker?.role == .others) // system track starts at 0 s
        #expect(ordered.last?.speaker?.role == .me)
    }

    @Test("With diarization, remote voices become numbered speakers")
    func transcribeMeetingWithSpeakers() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TranscriptionService(library: library, engine: FakeEngine(), diarizer: FakeDiarizer())
        let recording = try makeRecording(meeting: true)

        service.enqueue(recording)
        try await waitUntilIdle(service)

        let transcript = try #require(recording.transcript)
        let ordered = transcript.orderedSegments
        #expect(ordered.map(\.text) == ["Hallo von", "den anderen.", "Hallo, hier spreche ich."])
        #expect(ordered.map { $0.speaker?.displayName } == ["Sprecher 1", "Sprecher 2", "Ich"])
        #expect(transcript.speakers.count == 3)
    }

    @Test("The microphone is only split when the system track is nearly silent (or the setting is on)")
    func microphoneSplitting() {
        let online = (0..<40).map { Scripta.WordTiming(text: "wort", start: Double($0), end: Double($0) + 0.5) }
        #expect(TranscriptionService.microphoneNeedsSpeakers(system: online) == TranscriptionSettings.separatesRoomSpeakers)
        #expect(TranscriptionService.microphoneNeedsSpeakers(system: []))
    }

    @Test("A corrected speaker count goes to the system track, not to the microphone")
    func speakerCount() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let diarizer = FakeDiarizer()
        let service = TranscriptionService(library: library, engine: FakeEngine(), diarizer: diarizer)
        let recording = try makeRecording(meeting: true)

        service.enqueue(recording, speakerCount: 3)
        try await waitUntilIdle(service)

        let requests = diarizer.requests.withLock { $0 }
        #expect(requests["system"] == .some(3))
        #expect(requests["microphone"] == .some(nil)) // diarized (silent system track in the fake), no count
    }

    @Test("If diarization fails, the transcript keeps 'Ich' and 'Andere'")
    func diarizationFailure() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TranscriptionService(library: library, engine: FakeEngine(), diarizer: FakeDiarizer(fails: true))
        let recording = try makeRecording(meeting: true)

        service.enqueue(recording)
        try await waitUntilIdle(service)

        #expect(recording.status == .done)
        let transcript = try #require(recording.transcript)
        #expect(Set(transcript.speakers.map(\.role)) == [.me, .others])
    }

    @Test("Cancelling a running job returns the recording to 'not transcribed'")
    func cancelRunning() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TranscriptionService(library: library, engine: FakeEngine(delay: .seconds(10)))
        let recording = try makeRecording(meeting: false)

        service.enqueue(recording)
        try await Task.sleep(for: .milliseconds(200))
        #expect(service.runningID == recording.id)
        service.cancel(recording)
        try await waitUntilIdle(service)

        #expect(recording.status == .notTranscribed)
        #expect(recording.transcript == nil)
    }

    @Test("Failures are reported on the recording")
    func failure() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TranscriptionService(library: library, engine: FakeEngine(fails: true))
        let recording = try makeRecording(meeting: false)

        service.enqueue(recording)
        try await waitUntilIdle(service)

        #expect(recording.status == .failed)
        #expect(recording.errorMessage != nil)
    }

    @Test("Jobs run one after another in order")
    func ordering() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TranscriptionService(library: library, engine: FakeEngine(delay: .milliseconds(100)))
        let first = try makeRecording(meeting: false)
        let second = try makeRecording(meeting: false)

        service.enqueue(first)
        service.enqueue(second)
        service.enqueue(first) // duplicates are ignored
        #expect(service.queue == [first.id, second.id])
        try await Task.sleep(for: .milliseconds(50))
        #expect(service.runningID == first.id)
        #expect(second.status == .queued)
        try await waitUntilIdle(service)
        #expect(first.status == .done && second.status == .done)
    }

    @Test("Jobs interrupted by quitting are resumed")
    func resume() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = try makeRecording(meeting: false)
        recording.status = .running
        try library.save()

        let service = TranscriptionService(library: library, engine: FakeEngine())
        service.resumePendingJobs()
        try await waitUntilIdle(service)

        #expect(recording.status == .done)
    }
}

// MARK: - End to end with the real model

/// Runs only when the Parakeet model is installed (it is downloaded by the app
/// on first launch). Audio: synthetic speech generated with `say` (DE: Anna, EN: Samantha).
@Suite("Parakeet end to end", .enabled(if: ParakeetEngine.isModelInstalled), .serialized)
struct ParakeetEndToEndTests {
    private func resource(_ name: String) throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        return try #require(bundle.url(forResource: name, withExtension: "m4a"))
    }

    @Test("German speech")
    func german() async throws {
        let engine = ParakeetEngine()
        let result = try await engine.transcribe(fileURL: try resource("speech-de")) { _ in }
        let text = result.words.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("guten morgen"), "\(text)")
        #expect(text.contains("budget"), "\(text)")
        #expect(text.contains("quartal"), "\(text)")
        #expect(text.contains("freitag"), "\(text)")
        #expect(TranscriptBuilder.detectLanguage(of: text) == "de")
        // Timings are monotonic and inside the file.
        #expect(zip(result.words, result.words.dropFirst()).allSatisfy { $0.start <= $1.start })
        #expect((result.words.last?.end ?? 0) <= result.duration + 0.5)
    }

    @Test("English speech")
    func english() async throws {
        let engine = ParakeetEngine()
        let result = try await engine.transcribe(fileURL: try resource("speech-en")) { _ in }
        let text = result.words.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("good morning"), "\(text)")
        #expect(text.contains("roadmap") || text.contains("road map"), "\(text)")
        #expect(text.contains("friday"), "\(text)")
        #expect(TranscriptBuilder.detectLanguage(of: text) == "en")
    }
}

// MARK: - Speaker diarization with the real model

/// Runs only when the diarization model is installed (the app downloads it on
/// first launch). Audio: a dialogue generated with `say`, Samantha and Daniel
/// taking turns; each turn is followed by 0.7 s of silence.
@Suite("Speaker diarization end to end", .enabled(if: SpeakerDiarizer.isModelInstalled), .serialized)
struct SpeakerDiarizationEndToEndTests {
    /// Start and end of each turn in `speakers-en.m4a`.
    static let turns: [(start: TimeInterval, end: TimeInterval)] = [
        (0, 5.84), (6.54, 12.94), (13.64, 19.78), (20.48, 26.38), (27.08, 33.23), (33.93, 39.62),
    ]

    @Test("Two alternating voices are told apart")
    func dialogue() async throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "speakers-en", withExtension: "m4a"))
        let diarization = try await SpeakerDiarizer().diarize(fileURL: url) { _ in }

        #expect(diarization.speakers == [1, 2])
        #expect(Set(diarization.embeddings.keys) == [1, 2])
        #expect(diarization.embeddings[1]?.count == 256)
        // The speaker in the middle of each turn alternates: 1, 2, 1, 2, …
        let speakers = Self.turns.map { turn in
            let middle = (turn.start + turn.end) / 2
            return diarization.turns.first { $0.start <= middle && middle <= $0.end }?.speaker
        }
        #expect(speakers == [1, 2, 1, 2, 1, 2], "\(diarization.turns)")
    }

    @Test("A fixed number of speakers is respected")
    func fixedCount() async throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "speakers-en", withExtension: "m4a"))
        let one = try await SpeakerDiarizer().diarize(fileURL: url, speakerCount: 1) { _ in }
        #expect(one.speakers == [1])
        let three = try await SpeakerDiarizer().diarize(fileURL: url, speakerCount: 3) { _ in }
        #expect(three.speakers.count == 3)
    }

    @Test("Each sentence is attributed to its speaker", .enabled(if: ParakeetEngine.isModelInstalled))
    func attributedTranscript() async throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "speakers-en", withExtension: "m4a"))
        let diarization = try await SpeakerDiarizer().diarize(fileURL: url) { _ in }
        let words = try await ParakeetEngine().transcribe(fileURL: url) { _ in }.words
        let segments = TranscriptBuilder.segments(from: words, diarization: diarization)

        func speaker(saying phrase: String) -> SpeakerKey? {
            segments.first { $0.text.lowercased().contains(phrase) }?.speaker
        }
        #expect(speaker(saying: "release plan") == .diarized(1))
        #expect(speaker(saying: "budget") == .diarized(2))
        #expect(speaker(saying: "finance") == .diarized(1))
        #expect(speaker(saying: "migration") == .diarized(2))
        #expect(speaker(saying: "friday") == .diarized(1))
        #expect(speaker(saying: "fallback") == .diarized(2))
        #expect(Set(segments.compactMap(\.speaker)) == [.diarized(1), .diarized(2)])
    }
}

// MARK: - Recognizing voices with the real model

/// The voices of `speakers-en` (Samantha, Daniel) saying other sentences,
/// band-limited and compressed to 10 kbit/s Opus like a Teams call.
@MainActor
@Suite("Voice recognition end to end", .enabled(if: SpeakerDiarizer.isModelInstalled), .serialized)
struct VoiceRecognitionEndToEndTests {
    @Test("Named voices are suggested again in another recording over a call-like connection")
    func recognizeAcrossRecordings() async throws {
        let bundle = Bundle(for: BundleToken.self)
        let first = try await SpeakerDiarizer().diarize(fileURL: try #require(bundle.url(forResource: "speakers-en", withExtension: "m4a"))) { _ in }
        let second = try await SpeakerDiarizer().diarize(fileURL: try #require(bundle.url(forResource: "speakers-en-teams", withExtension: "m4a"))) { _ in }

        let voices = VoiceLibrary.makeInMemory(isEnabled: { true })
        func labelVoices(_ diarization: Diarization) -> [Int: LabelVoice] {
            Dictionary(uniqueKeysWithValues: diarization.speakers.map { speaker in
                (speaker, LabelVoice(labelID: UUID(), embedding: diarization.embeddings[speaker] ?? [], speechSeconds: diarization.speechDuration(of: speaker)))
            })
        }
        let known = labelVoices(first)
        _ = voices.recognize(Array(known.values), recordingID: UUID())
        voices.link(labelID: try #require(known[1]).labelID, toPersonNamed: "Samantha")
        voices.link(labelID: try #require(known[2]).labelID, toPersonNamed: "Daniel")

        // Daniel speaks first in the second recording.
        let fresh = labelVoices(second)
        _ = voices.recognize(Array(fresh.values), recordingID: UUID())
        #expect(voices.statuses[try #require(fresh[1]).labelID]?.personName == "Daniel")
        #expect(voices.statuses[try #require(fresh[2]).labelID]?.personName == "Samantha")
        #expect(voices.statuses[try #require(fresh[1]).labelID]?.state == .suggested)
        let score = voices.statuses[try #require(fresh[1]).labelID]?.score ?? 0
        #expect(score >= Double(VoiceMatcher.automaticThreshold), "\(score)")
    }
}

private final class BundleToken {}
