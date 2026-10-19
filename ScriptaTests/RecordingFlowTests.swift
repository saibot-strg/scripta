import Foundation
import SwiftData
import Testing
@testable import Scripta

/// End-to-end flow through `AppModel`: record (test tone), stop, select, play, encode.
@MainActor
@Suite("Recording flow")
struct RecordingFlowTests {
    let root = TestAudio.temporaryDirectory()
    /// On-disk SQLite store like the app uses: object IDs change on save
    /// there, which the in-memory store doesn't reproduce.
    let container: ModelContainer

    init() throws {
        container = try TestStore.makeContainer()
    }

    private func makeAppModel() -> AppModel {
        let library = LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: root))
        let model = AppModel(library: library)
        model.recorder.usesTestTone = true
        return model
    }

    @Test("A new recording is selected, playable and encoded to AAC after stopping")
    func recordStopPlay() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeAppModel()

        await model.startRecording()
        #expect(model.recorder.state == .recording)
        try await Task.sleep(for: .milliseconds(700))
        model.stopRecording()

        // Regression: the fresh recording must resolve right after saving
        // (SwiftData's persistentModelID changes on save).
        let recording = try #require(model.selectedRecording)
        #expect(recording.status == .notTranscribed)
        #expect(recording.duration > 0.3)

        model.loadPlayer(for: recording)
        #expect(model.player.isAvailable)

        // Background AAC encoding replaces the PCM file of this very recording.
        let deadline = ContinuousClock.now + .seconds(5)
        while recording.primaryTrack?.fileName != CaptureFormat.encodedFileName(for: CaptureFormat.fileName), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(recording.primaryTrack?.fileName == CaptureFormat.encodedFileName(for: CaptureFormat.fileName))
        let url = try #require(model.library.audioURL(for: recording))
        #expect(url.lastPathComponent == CaptureFormat.encodedFileName(for: CaptureFormat.fileName))
        // The player switched to the encoded file.
        #expect(model.player.loadedURL == url)
    }

    @Test("Pause excludes time from the recorded duration")
    func pauseAndResume() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeAppModel()

        await model.startRecording()
        try await Task.sleep(for: .milliseconds(500))
        model.togglePause()
        #expect(model.recorder.state == .paused)
        try await Task.sleep(for: .milliseconds(800))
        model.togglePause()
        // Resuming is asynchronous (system audio restarts on its own queue).
        let deadline = ContinuousClock.now + .seconds(2)
        while model.recorder.state != .recording, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.recorder.state == .recording)
        try await Task.sleep(for: .milliseconds(500))
        model.stopRecording()

        let recording = try #require(model.selectedRecording)
        // About 1 s recorded; the 0.8 s pause is not included.
        #expect(recording.duration > 0.7 && recording.duration < 1.5, "duration \(recording.duration)")
    }

    @Test("Deleting the selected recording clears the selection and the player")
    func deleteSelected() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeAppModel()
        await model.startRecording()
        try await Task.sleep(for: .milliseconds(300))
        model.stopRecording()
        let recording = try #require(model.selectedRecording)
        model.loadPlayer(for: recording)

        model.delete(recording)

        #expect(model.selectedRecordingID == nil)
        #expect(!model.player.isAvailable)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 0)
    }
}
