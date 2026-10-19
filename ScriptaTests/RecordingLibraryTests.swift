import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Scripta

@MainActor
@Suite("Recording storage, recovery and playback")
struct RecordingLibraryTests {
    let container = ModelContainerFactory.makeInMemory()
    let root = TestAudio.temporaryDirectory()

    var storage: RecordingStorage { RecordingStorage(rootURL: root) }
    var library: LibraryService { LibraryService(modelContext: container.mainContext, storage: storage) }

    /// Simulates a recording interrupted by a crash: manifest plus unfinished file.
    private func makeInterruptedRecording(duration: TimeInterval, title: String = "Notiz") throws -> RecordingManifest {
        let manifest = RecordingManifest(id: UUID(), title: title, createdAt: .now, source: .microphone, fileName: CaptureFormat.fileName)
        try storage.makeFolder(for: manifest.id)
        try storage.writeManifest(manifest)
        let sink = try AudioFileSink(fileURL: storage.fileURL(for: manifest.id, fileName: manifest.fileName))
        if duration > 0 {
            TestAudio.feed(sink, sampleRate: 48_000, channels: 1, duration: duration)
        }
        // Intentionally not finished: the process "crashed".
        return manifest
    }

    @Test("A finished recording becomes a library entry and loses its manifest")
    func addRecording() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try makeInterruptedRecording(duration: 1)
        let recording = try library.addRecording(manifest: manifest, duration: 1)

        #expect(recording.status == .notTranscribed)
        #expect(recording.source == .microphone)
        #expect(recording.primaryTrack?.fileName == CaptureFormat.fileName)
        #expect(library.audioURL(for: recording) != nil)
        #expect(!FileManager.default.fileExists(atPath: storage.manifestURL(for: manifest.id).path(percentEncoded: false)))
    }

    @Test("Interrupted recordings are recovered with their audio")
    func recovery() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try makeInterruptedRecording(duration: 2, title: "Absturz-Test")

        let recovered = await RecordingRecovery(library: library).recoverInterruptedRecordings()

        #expect(recovered == 1)
        let recording = try #require(library.recording(withID: manifest.id))
        #expect(recording.title.hasPrefix("Absturz-Test"))
        #expect(recording.title != "Absturz-Test") // marked as recovered
        #expect(abs(recording.duration - 2) < 0.02)
        #expect(recording.status == .notTranscribed)
        // Running recovery again changes nothing.
        #expect(await RecordingRecovery(library: library).recoverInterruptedRecordings() == 0)
    }

    @Test("A leftover manifest of a saved recording is just removed")
    func recoveryOfSavedRecording() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try makeInterruptedRecording(duration: 1)
        let recording = Recording(id: manifest.id, title: manifest.title, source: .microphone)
        container.mainContext.insert(recording)

        #expect(await RecordingRecovery(library: library).recoverInterruptedRecordings() == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(!FileManager.default.fileExists(atPath: storage.manifestURL(for: manifest.id).path(percentEncoded: false)))
    }

    @Test("An interrupted recording without audio is discarded")
    func recoveryWithoutAudio() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try makeInterruptedRecording(duration: 0)

        #expect(await RecordingRecovery(library: library).recoverInterruptedRecordings() == 0)
        #expect(!FileManager.default.fileExists(atPath: storage.folderURL(for: manifest.id).path(percentEncoded: false)))
    }

    @Test("Replacing a track's file deletes the old one")
    func replaceFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try makeInterruptedRecording(duration: 1)
        let recording = try library.addRecording(manifest: manifest, duration: 1)
        let encodedName = CaptureFormat.encodedFileName(for: CaptureFormat.fileName)
        let newURL = storage.fileURL(for: manifest.id, fileName: encodedName)
        try Data("m4a".utf8).write(to: newURL)

        try library.replaceFile(of: try #require(recording.primaryTrack), in: recording, with: encodedName)

        #expect(recording.primaryTrack?.fileName == encodedName)
        #expect(!FileManager.default.fileExists(atPath: storage.fileURL(for: manifest.id, fileName: CaptureFormat.fileName).path(percentEncoded: false)))
    }

    @Test("Player loads a recording, seeks and clamps skips")
    func player() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try makeInterruptedRecording(duration: 4)
        let recording = try library.addRecording(manifest: manifest, duration: 4)
        let player = PlayerModel()

        player.load(library.audioURL(for: recording))
        #expect(player.isAvailable)
        #expect(abs(player.duration - 4) < 0.05)

        player.seek(to: 2)
        #expect(player.currentTime == 2)
        player.skip(by: -PlayerModel.skipInterval)
        #expect(player.currentTime == 0)
        player.skip(by: PlayerModel.skipInterval)
        #expect(player.currentTime == player.duration)

        player.beginScrubbing()
        player.scrub(to: 1.5)
        #expect(player.currentTime == 1.5)
        player.endScrubbing()
        #expect(!player.isScrubbing)

        player.unload()
        #expect(!player.isAvailable)
        player.load(nil)
        #expect(!player.isAvailable)
    }
}
