import Foundation
import SwiftData
import Testing
@testable import Scripta

@MainActor
@Suite("Storage locations")
struct StorageLocationTests {
    let root = TestAudio.temporaryDirectory()
    let container: ModelContainer
    let defaults: UserDefaults

    init() throws {
        container = try TestStore.makeContainer()
        defaults = try #require(UserDefaults(suiteName: "ScriptaTests-\(UUID().uuidString)"))
    }

    private func makeLibrary() -> LibraryService {
        let locations = StorageLocations(defaults: defaults, defaultStorage: RecordingStorage(rootURL: root.appending(path: "Default")))
        return LibraryService(modelContext: container.mainContext, locations: locations)
    }

    /// Writes a short recording into the current location and adds it.
    private func record(in library: LibraryService) throws -> Recording {
        let manifest = RecordingManifest(id: UUID(), title: "Notiz", createdAt: .now, source: .microphone, fileName: CaptureFormat.fileName)
        try library.storage.makeFolder(for: manifest.id)
        let sink = try AudioFileSink(fileURL: library.storage.fileURL(for: manifest.id, fileName: manifest.fileName))
        TestAudio.feed(sink, sampleRate: 48_000, channels: 1, duration: 0.5)
        sink.finish()
        return try library.addRecording(manifest: manifest, duration: 0.5, rootBookmark: library.locations.currentBookmark)
    }

    @Test("New recordings go to the chosen folder; older ones stay reachable")
    func changeLocation() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = makeLibrary()
        let before = try record(in: library)
        #expect(library.audioURL(for: before)?.path(percentEncoded: false).contains("/Default/") == true)

        let custom = root.appending(path: "Extern", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try library.locations.use(custom)
        let after = try record(in: library)

        #expect(after.storageRootBookmark != nil)
        #expect(library.audioURL(for: after)?.path(percentEncoded: false).contains("/Extern/") == true)
        #expect(library.audioURL(for: before) != nil)

        // The choice survives a relaunch (new StorageLocations reading the same defaults).
        let relaunched = LibraryService(modelContext: container.mainContext, locations: StorageLocations(
            defaults: defaults, defaultStorage: RecordingStorage(rootURL: root.appending(path: "Default"))
        ))
        #expect(relaunched.storage.rootURL.standardizedFileURL == custom.standardizedFileURL)
        #expect(relaunched.audioURL(for: after) != nil)

        library.locations.useDefault()
        #expect(library.locations.isDefault)
        #expect(library.audioURL(for: after) != nil)

        // Deleting removes the files in the recording's own location.
        let folder = try #require(library.audioURL(for: after)).deletingLastPathComponent()
        try library.delete(after)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test("Interrupted recordings are recovered from every location")
    func recoveryAcrossLocations() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = makeLibrary()
        let custom = root.appending(path: "Extern", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)

        for useCustom in [false, true] {
            if useCustom { try library.locations.use(custom) }
            let manifest = RecordingManifest(id: UUID(), title: "Abgebrochen", createdAt: .now, source: .microphone, fileName: CaptureFormat.fileName)
            try library.storage.makeFolder(for: manifest.id)
            try library.storage.writeManifest(manifest)
            let sink = try AudioFileSink(fileURL: library.storage.fileURL(for: manifest.id, fileName: manifest.fileName))
            TestAudio.feed(sink, sampleRate: 48_000, channels: 1, duration: 0.5)
            sink.finish()
        }

        #expect(await RecordingRecovery(library: library).recoverInterruptedRecordings() == 2)
        let recordings = try container.mainContext.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 2)
        #expect(recordings.allSatisfy { library.audioURL(for: $0) != nil })
        #expect(recordings.filter { $0.storageRootBookmark != nil }.count == 1)
    }
}

@MainActor
@Suite("Transcript editing")
struct TranscriptEditingTests {
    let container = ModelContainerFactory.makeInMemory()

    private func makeModelWithTranscript() -> (AppModel, Recording) {
        let model = AppModel(library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())))
        let recording = Recording(title: "Meeting", source: .meeting, status: .done)
        container.mainContext.insert(recording)
        let transcript = Transcript(languageCode: "de", engineIdentifier: "test")
        recording.transcript = transcript
        let others = SpeakerLabel(role: .others)
        let me = SpeakerLabel(role: .me)
        transcript.speakers.append(contentsOf: [others, me])
        let words = [Scripta.WordTiming(text: "Halo", start: 0, end: 0.4, confidence: 1), Scripta.WordTiming(text: "Welt.", start: 0.5, end: 0.9, confidence: 1)]
        let first = TranscriptSegment(index: 0, start: 0, end: 0.9, text: "Halo Welt.", words: words)
        let second = TranscriptSegment(index: 1, start: 1, end: 2, text: "Hallo zurück.")
        transcript.segments.append(contentsOf: [first, second])
        first.speaker = others
        second.speaker = me
        transcript.rebuildFullText()
        return (model, recording)
    }

    @Test("Corrections are saved, searchable and exported without stale word timings")
    func editing() throws {
        let (model, recording) = makeModelWithTranscript()
        let segment = try #require(recording.transcript?.orderedSegments.first)

        model.edit(segment, text: "  Hallo Welt.  ")

        #expect(segment.text == "Hallo Welt.")
        #expect(segment.originalText == "Halo Welt.")
        #expect(recording.matches(searchText: "Hallo Welt"))
        let document = try #require(model.exportDocument(for: recording))
        #expect(document.segments[0].text == "Hallo Welt.")
        #expect(document.segments[0].words.isEmpty)

        // Empty input is ignored.
        model.edit(segment, text: "   ")
        #expect(segment.text == "Hallo Welt.")

        model.restoreOriginalText(of: segment)
        #expect(segment.text == "Halo Welt.")
        #expect(!segment.isEdited)
    }

    @Test("Renaming a speaker applies everywhere; the default name stays localized")
    func renameSpeaker() throws {
        let (model, recording) = makeModelWithTranscript()
        let others = try #require(recording.transcript?.speakers.first { $0.role == .others })

        model.rename(others, to: "Anna")
        #expect(others.displayName == "Anna")
        #expect(model.exportDocument(for: recording)?.segments.first?.speaker == "Anna")

        model.rename(others, to: others.defaultName)
        #expect(others.customName == nil)
        model.rename(others, to: "  ")
        #expect(others.customName == nil)
    }
}
