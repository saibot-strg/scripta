import Foundation
import FluidAudio
import SwiftData
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

private final class BundleToken {}
