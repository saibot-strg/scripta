import AVFoundation
import CoreVideo
import Foundation
import SwiftData
import Testing
@testable import Scripta

/// Creates media files for import tests.
enum TestMedia {
    static func speechURL() throws -> URL {
        try #require(Bundle(for: MediaToken.self).url(forResource: "speech-de", withExtension: "m4a"))
    }

    /// PCM or FLAC file with a tone.
    static func writeTone(to url: URL, settings: [String: Any], duration: TimeInterval) throws {
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: TestAudio.tone(sampleRate: 44_100, channels: 1, duration: duration))
    }

    /// A small H.264 movie, optionally with the German test speech as audio track.
    static func writeMovie(to url: URL, duration: Double, audio: URL?) async throws {
        let videoOnly = url.deletingLastPathComponent().appending(path: "video-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: videoOnly) }

        let writer = try AVAssetWriter(outputURL: videoOnly, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0...Int(duration * 2) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            adaptor.append(try #require(pixelBuffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 2))
        }
        input.markAsFinished()
        await writer.finishWriting()

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoOnly)
        let videoTrack = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let videoRange = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(videoRange, of: videoTrack, at: .zero)
        if let audio {
            let audioAsset = AVURLAsset(url: audio)
            let audioTrack = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
            let audioRange = CMTimeRange(start: .zero, duration: try await audioAsset.load(.duration))
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
                .insertTimeRange(audioRange, of: audioTrack, at: .zero)
        }
        let export = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await export.export(to: url, as: .mov)
    }
}

private final class MediaToken {}

@Suite("Audio import")
struct AudioImportTests {
    let root = TestAudio.temporaryDirectory()
    var storage: RecordingStorage { RecordingStorage(rootURL: root.appending(path: "Library")) }

    private func checksum(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    @Test("Audio files are copied unchanged; the original stays untouched", arguments: ["wav", "flac", "m4a"])
    func audioFile(format: String) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source: URL
        switch format {
        case "wav":
            source = root.appending(path: "Interview.wav")
            try TestMedia.writeTone(to: source, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                                                           AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16], duration: 2)
        case "flac":
            source = root.appending(path: "Interview.flac")
            try TestMedia.writeTone(to: source, settings: [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 44_100,
                                                           AVNumberOfChannelsKey: 1], duration: 2)
        default:
            source = root.appending(path: "Interview.m4a")
            try FileManager.default.copyItem(at: try TestMedia.speechURL(), to: source)
        }
        let before = try checksum(source)
        let modified = try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let prepared = try await AudioImporter.prepare(source, storage: storage)

        #expect(prepared.manifest.title == "Interview")
        #expect(prepared.manifest.source == .importedFile)
        #expect(prepared.manifest.fileName == "original.\(format)")
        let imported = storage.fileURL(for: prepared.manifest.id, fileName: prepared.manifest.fileName)
        #expect(try checksum(imported) == before) // bit-identical copy
        #expect(try checksum(source) == before)   // original untouched
        #expect(try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(prepared.duration > 1.5)
        #expect(storage.readManifest(in: storage.folderURL(for: prepared.manifest.id)) != nil)
    }

    @Test("Videos keep only their audio track")
    func video() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appending(path: "Call-Aufzeichnung.mov")
        try await TestMedia.writeMovie(to: movie, duration: 7, audio: try TestMedia.speechURL())

        let prepared = try await AudioImporter.prepare(movie, storage: storage)

        #expect(prepared.manifest.fileName == "audio.m4a")
        let imported = storage.fileURL(for: prepared.manifest.id, fileName: prepared.manifest.fileName)
        let tracks = try await AVURLAsset(url: imported).load(.tracks)
        #expect(tracks.allSatisfy { $0.mediaType == .audio })
        #expect(abs(prepared.duration - 6.8) < 0.3, "duration \(prepared.duration)")
    }

    @Test("A video without sound is rejected and leaves nothing behind")
    func silentVideo() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appending(path: "Stumm.mov")
        try await TestMedia.writeMovie(to: movie, duration: 2, audio: nil)

        await #expect(throws: ImportError.self) {
            try await AudioImporter.prepare(movie, storage: storage)
        }
        #expect(storage.recordingFolders().isEmpty)
    }

    @Test("Other files are rejected with a clear message")
    func unsupported() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let text = root.appending(path: "Notizen.txt")
        try Data("Kein Audio".utf8).write(to: text)

        do {
            _ = try await AudioImporter.prepare(text, storage: storage)
            Issue.record("Import should fail")
        } catch {
            #expect(error.fileName == "Notizen.txt")
            #expect(error.errorDescription?.contains("Notizen.txt") == true)
        }
        #expect(storage.recordingFolders().isEmpty)
    }
}

@MainActor
@Suite("Import into the library")
struct LibraryImportTests {
    let root = TestAudio.temporaryDirectory()
    let container: ModelContainer

    init() throws {
        container = try TestStore.makeContainer()
    }

    private func makeAppModel() -> AppModel {
        AppModel(library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: root.appending(path: "Recordings"))))
    }

    private func waitForImport(_ model: AppModel) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while model.importStatus?.isFinished != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Several files at once: good ones land in the library, bad ones are reported")
    func batch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeAppModel()
        let first = root.appending(path: "Eins.m4a"), second = root.appending(path: "Zwei.m4a"), broken = root.appending(path: "Kaputt.mp3")
        try FileManager.default.copyItem(at: try TestMedia.speechURL(), to: first)
        try FileManager.default.copyItem(at: try TestMedia.speechURL(), to: second)
        try Data("kein mp3".utf8).write(to: broken)

        model.importFiles([first, broken, second])
        try await waitForImport(model)

        let status = try #require(model.importStatus)
        #expect(status.completed == 3)
        #expect(status.importedIDs.count == 2)
        let recordings = try container.mainContext.fetch(FetchDescriptor<Recording>())
        #expect(Set(recordings.map(\.title)) == ["Eins", "Zwei"])
        #expect(recordings.allSatisfy { $0.source == .importedFile && $0.status == .notTranscribed })
        #expect(model.presentedError?.message?.contains("Kaputt.mp3") == true)
        // The last imported recording is selected.
        #expect(model.selectedRecording?.title == "Zwei")
    }
}

/// Import → transcribe with the real model.
@MainActor
@Suite("Import end to end", .enabled(if: ParakeetEngine.isModelInstalled))
struct ImportEndToEndTests {
    @Test("An imported German file is transcribed")
    func importAndTranscribe() async throws {
        let root = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try TestStore.makeContainer()
        let model = AppModel(library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: root.appending(path: "Recordings"))))
        let movie = root.appending(path: "Teammeeting.mov")
        try await TestMedia.writeMovie(to: movie, duration: 7, audio: try TestMedia.speechURL())

        model.importFiles([movie])
        var deadline = ContinuousClock.now + .seconds(10)
        while model.importStatus?.isFinished != true, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        model.transcribeImported()

        let recording = try #require(model.selectedRecording)
        deadline = ContinuousClock.now + .seconds(60)
        while recording.status != .done, recording.status != .failed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(recording.status == .done)
        let text = recording.transcript?.fullText.lowercased() ?? ""
        #expect(text.contains("budget"), "\(text)")
        #expect(recording.languageCode == "de")
    }
}
