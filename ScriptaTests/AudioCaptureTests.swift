import AVFoundation
import Foundation
import Testing
@testable import Scripta

@Suite("Audio capture and encoding")
struct AudioCaptureTests {
    @Test("Input in any format ends up as 48 kHz mono with the right duration", arguments: [
        (44_100.0, AVAudioChannelCount(2)),
        (48_000.0, 1),
        (16_000.0, 1),
        (96_000.0, 2),
    ])
    func convertsToCaptureFormat(sampleRate: Double, channels: AVAudioChannelCount) throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: CaptureFormat.fileName)

        let sink = try AudioFileSink(fileURL: url)
        TestAudio.feed(sink, sampleRate: sampleRate, channels: channels, duration: 2)
        let reported = sink.finish()

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == CaptureFormat.sampleRate)
        #expect(file.fileFormat.channelCount == 1)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        // Resampling keeps a few milliseconds in the converter.
        #expect(abs(duration - 2) < 0.02, "duration \(duration)")
        #expect(abs(reported - duration) < 0.001)
    }

    @Test("The file is readable while recording is still running (crash safety)")
    func readableBeforeFinish() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: CaptureFormat.fileName)
        let sink = try AudioFileSink(fileURL: url)
        TestAudio.feed(sink, sampleRate: 48_000, channels: 1, duration: 3)

        // Snapshot the file as a crash would leave it: never closed.
        let snapshot = folder.appending(path: "crashed.caf")
        try FileManager.default.copyItem(at: url, to: snapshot)
        let file = try AVAudioFile(forReading: snapshot)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        #expect(abs(duration - 3) < 0.01, "duration \(duration)")

        // Audio content survives, not only the header.
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(buffer.floatChannelData![0][index])) }
        #expect(peak > 0.45)
        sink.finish()
    }

    @Test("Meter levels: 20 per second, loud tone near the top, silence at zero")
    func meterLevels() async throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = try AudioFileSink(fileURL: folder.appending(path: CaptureFormat.fileName))
        TestAudio.feed(sink, sampleRate: 48_000, channels: 1, duration: 1)
        sink.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 0.5, amplitude: 0))
        sink.finish()

        var levels: [Float] = []
        for await event in sink.events {
            if case .progress(let newLevels, _) = event { levels += newLevels }
        }
        #expect(levels.count == 30)
        #expect(levels.prefix(20).allSatisfy { $0 > 0.8 })
        #expect(levels.suffix(10).allSatisfy { $0 == 0 })
    }

    @Test("Level mapping covers -50…0 dBFS")
    func levelMapping() {
        #expect(LevelMeter.normalizedLevel(rms: 0) == 0)
        #expect(LevelMeter.normalizedLevel(rms: 1) == 1)
        #expect(LevelMeter.normalizedLevel(rms: 0.001) == 0) // -60 dB
        #expect(abs(LevelMeter.normalizedLevel(rms: 0.0562) - 0.5) < 0.01) // -25 dB
    }

    @Test("AAC encoding keeps the duration and shrinks the file")
    func aacEncoding() async throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: CaptureFormat.fileName)
        let destination = folder.appending(path: CaptureFormat.encodedFileName(for: CaptureFormat.fileName))
        let sink = try AudioFileSink(fileURL: source)
        TestAudio.feed(sink, sampleRate: 48_000, channels: 1, duration: 5)
        sink.finish()

        try await AudioEncoder.encodeAAC(source: source, destination: destination, bitRate: 64_000)

        let duration = try #require(AudioFileInfo.duration(of: destination))
        #expect(abs(duration - 5) < 0.1, "duration \(duration)")
        let sourceSize = try #require(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let encodedSize = try #require(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(encodedSize * 5 < sourceSize, "\(encodedSize) vs \(sourceSize)")
        // No temporary files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(Set(leftovers) == [CaptureFormat.fileName, CaptureFormat.encodedFileName(for: CaptureFormat.fileName)])
    }
}
