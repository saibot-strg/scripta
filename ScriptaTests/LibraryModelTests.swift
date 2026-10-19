import Foundation
import SwiftData
import Testing
@testable import Scripta

@MainActor
@Suite("Library models")
struct LibraryModelTests {
    let container = ModelContainerFactory.makeInMemory()
    var context: ModelContext { container.mainContext }

    @Test("Enums round-trip through their stored raw values")
    func enumRoundTrip() {
        let recording = Recording(title: "Test", source: .meeting, status: .queued)
        #expect(recording.sourceRaw == "meeting")
        #expect(recording.source == .meeting)
        recording.status = .failed
        #expect(recording.statusRaw == "failed")
        #expect(recording.status == .failed)
    }

    @Test("Unknown raw values fall back to safe defaults")
    func unknownRawValues() {
        let recording = Recording(title: "Test", source: .microphone)
        recording.statusRaw = "somethingNew"
        recording.sourceRaw = "somethingNew"
        #expect(recording.status == .notTranscribed)
        #expect(recording.source == .importedFile)
    }

    @Test("Search matches title and transcript text, ignoring case and diacritics")
    func searchMatching() throws {
        let recording = Recording(title: "Team-Weekly", source: .meeting, status: .done)
        context.insert(recording)
        let transcript = Transcript(languageCode: "de", engineIdentifier: "test")
        recording.transcript = transcript
        transcript.segments.append(TranscriptSegment(index: 0, start: 0, end: 2, text: "Wir besprechen die Größe des Releases."))
        transcript.rebuildFullText()

        #expect(recording.matches(searchText: ""))
        #expect(recording.matches(searchText: "weekly"))
        #expect(recording.matches(searchText: "GRÖßE"))   // case-insensitive
        #expect(recording.matches(searchText: "groß"))    // diacritic-insensitive (ö ≈ o)
        #expect(recording.matches(searchText: "release"))
        #expect(recording.matches(searchText: "Budget") == false)
    }

    @Test("Segments are ordered by start time, then index")
    func segmentOrdering() {
        let recording = Recording(title: "Order", source: .microphone)
        context.insert(recording)
        let transcript = Transcript(engineIdentifier: "test")
        recording.transcript = transcript
        transcript.segments.append(TranscriptSegment(index: 2, start: 5, end: 6, text: "C"))
        transcript.segments.append(TranscriptSegment(index: 0, start: 0, end: 1, text: "A"))
        transcript.segments.append(TranscriptSegment(index: 1, start: 0, end: 2, text: "B"))
        transcript.rebuildFullText()

        #expect(transcript.orderedSegments.map(\.text) == ["A", "B", "C"])
        #expect(transcript.fullText == "A\nB\nC")
    }

    @Test("Editing a segment keeps the engine's original text once")
    func segmentEditing() {
        let segment = TranscriptSegment(index: 0, start: 0, end: 1, text: "Halo Welt")
        #expect(!segment.isEdited)
        segment.applyEdit("Hallo Welt")
        segment.applyEdit("Hallo, Welt!")
        #expect(segment.isEdited)
        #expect(segment.text == "Hallo, Welt!")
        #expect(segment.originalText == "Halo Welt")
    }

    @Test("Word timings survive the JSON blob")
    func wordTimings() {
        let words = [WordTiming(text: "Hallo", start: 0.1, end: 0.4, confidence: 0.98),
                     WordTiming(text: "Welt", start: 0.5, end: 0.9, confidence: nil)]
        let segment = TranscriptSegment(index: 0, start: 0.1, end: 0.9, text: "Hallo Welt", words: words)
        #expect(segment.words == words)
        #expect(TranscriptSegment(index: 1, start: 0, end: 0, text: "").wordsData == nil)
    }

    @Test("Speaker names are generated unless the user set one")
    func speakerNames() {
        let speaker = SpeakerLabel(role: .diarized, number: 2)
        #expect(speaker.displayName.contains("2"))
        speaker.customName = "Anna"
        #expect(speaker.displayName == "Anna")
        #expect(SpeakerLabel(role: .me).isLocalUser)
    }

    @Test("Deleting a recording cascades to transcript, segments and speakers")
    func cascadeDelete() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = LibraryService(modelContext: context, storage: RecordingStorage(rootURL: root))
        try service.insertSampleData()
        #expect(try context.fetchCount(FetchDescriptor<Recording>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<TranscriptSegment>()) > 0)

        try service.deleteAll()

        #expect(try context.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transcript>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TranscriptSegment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SpeakerLabel>()) == 0)
    }

    @Test("Deleting a recording removes its folder on disk")
    func deleteRemovesFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = RecordingStorage(rootURL: root)
        let service = LibraryService(modelContext: context, storage: storage)
        let recording = Recording(title: "Mit Datei", source: .microphone)
        context.insert(recording)
        try service.save()

        let folder = try storage.makeFolder(for: recording.id)
        try Data("audio".utf8).write(to: folder.appending(path: "primary.m4a"))
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))

        try service.delete(recording)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test("Renaming trims whitespace and ignores empty titles")
    func rename() throws {
        let service = LibraryService(modelContext: context, storage: RecordingStorage(rootURL: temporaryRoot()))  // never touches disk
        let recording = Recording(title: "Alt", source: .microphone)
        context.insert(recording)
        try service.rename(recording, to: "  Neu  ")
        #expect(recording.title == "Neu")
        try service.rename(recording, to: "   ")
        #expect(recording.title == "Neu")
    }

    private func temporaryRoot() -> URL {
        URL.temporaryDirectory.appending(path: "ScriptaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
