import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Scripta

@MainActor
@Suite("Meeting recording")
struct MeetingTests {
    let root = TestAudio.temporaryDirectory()
    let container: ModelContainer

    init() throws {
        container = try TestStore.makeContainer()
    }

    var storage: RecordingStorage { RecordingStorage(rootURL: root) }

    private func makeAppModel() -> AppModel {
        let model = AppModel(library: LibraryService(modelContext: container.mainContext, storage: storage))
        model.recorder.usesTestTone = true
        return model
    }

    private func writeTone(_ url: URL, duration: TimeInterval, amplitude: Float) throws {
        let sink = try AudioFileSink(fileURL: url)
        let chunks = Int(duration / 0.1)
        for _ in 0..<chunks {
            sink.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 0.1, amplitude: amplitude))
        }
        sink.finish()
    }

    @Test("Mixing sums the tracks, keeps the longer duration and never clips past ±1")
    func mixing() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "a.caf"), second = root.appending(path: "b.caf"), output = root.appending(path: "mix.caf")
        try writeTone(first, duration: 2, amplitude: 0.7)
        try writeTone(second, duration: 3, amplitude: 0.7)

        let duration = try await AudioMixer.mix([first, second, root.appending(path: "missing.caf")], into: output)

        #expect(abs(duration - 3) < 0.01)
        let file = try AVAudioFile(forReading: output)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(buffer.floatChannelData![0][index])) }
        #expect(peak <= 1.0)
        #expect(peak > 0.99) // 0.7 + 0.7 in phase, clipped
    }

    @Test("A meeting records two tracks, mixes them and stores all three")
    func meetingFlow() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeAppModel()

        await model.startMeeting(.allSystemAudio)
        #expect(model.recorder.state == .recording)
        #expect(model.recorder.isMeeting)
        try await Task.sleep(for: .milliseconds(800))
        #expect(!model.recorder.systemLevels.isEmpty)
        #expect(!model.recorder.levels.isEmpty)
        await model.stopRecording()?.value

        // Mixing runs in the background.
        let deadline = ContinuousClock.now + .seconds(5)
        while model.selectedRecording == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let recording = try #require(model.selectedRecording)
        #expect(recording.source == .meeting)
        #expect(Set(recording.tracks.map(\.role)) == [.primary, .microphone, .system])
        #expect(recording.duration > 0.5)
        for role in [TrackRole.primary, .microphone, .system] {
            #expect(model.library.audioURL(for: recording, role: role) != nil, "missing \(role)")
        }
        #expect(!model.isSavingRecording)
        try await model.waitForEncoding()
    }

    @Test("An interrupted meeting is mixed and recovered on the next launch")
    func meetingRecovery() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = RecordingManifest(
            id: UUID(), title: "Weekly", createdAt: .now, source: .meeting, fileName: CaptureFormat.mixFileName,
            microphoneFileName: CaptureFormat.microphoneFileName, systemFileName: CaptureFormat.systemFileName
        )
        try storage.makeFolder(for: manifest.id)
        try storage.writeManifest(manifest)
        try writeTone(storage.fileURL(for: manifest.id, fileName: CaptureFormat.microphoneFileName), duration: 1, amplitude: 0.3)
        try writeTone(storage.fileURL(for: manifest.id, fileName: CaptureFormat.systemFileName), duration: 2, amplitude: 0.3)
        let library = LibraryService(modelContext: container.mainContext, storage: storage)

        let recovered = await RecordingRecovery(library: library).recoverInterruptedRecordings()

        #expect(recovered == 1)
        let recording = try #require(library.recording(withID: manifest.id))
        #expect(abs(recording.duration - 2) < 0.02)
        #expect(recording.tracks.count == 3)
        #expect(library.audioURL(for: recording) != nil)
    }

    @Test("Recovery skips the recording that is currently running")
    func recoverySkipsActiveRecording() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeAppModel()
        await model.startRecording()
        try await Task.sleep(for: .milliseconds(300))

        let recovered = await RecordingRecovery(library: model.library)
            .recoverInterruptedRecordings(activeRecordingID: { model.recorder.activeRecordingID })

        #expect(recovered == 0)
        await model.stopRecording()?.value
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
        try await model.waitForEncoding()
    }

    @Test("Manifests written before meetings existed still decode")
    func manifestCompatibility() throws {
        let json = #"{"createdAt":"2026-10-18T09:57:31Z","fileName":"recording.caf","id":"561E11F7-ACFC-4B4C-BB1A-33DA4A6B34B9","source":"microphone","title":"Alt"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(RecordingManifest.self, from: Data(json.utf8))
        #expect(!manifest.isMeeting)
        #expect(manifest.capturedFileNames == ["recording.caf"])
    }
}
