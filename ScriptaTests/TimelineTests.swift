import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import Scripta

@Suite("Track timeline (meeting alignment)")
struct TimelineTests {
    private func hostTime(_ origin: UInt64, plus seconds: Double) -> UInt64 {
        origin + AudioConvertNanosToHostTime(UInt64(seconds * 1e9))
    }

    private func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    @Test("Audio arriving later is placed at its capture time; the gap becomes silence")
    func gapIsFilled() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "system.caf")
        let sink = try AudioFileSink(fileURL: url, usesTimeline: true)
        let origin = mach_absolute_time()
        sink.startTimeline(at: origin)

        // "Andere" starts talking 10 s into the meeting.
        sink.append(TestAudio.tone(sampleRate: 48_000, channels: 2, duration: 1), hostTime: hostTime(origin, plus: 10))
        let duration = sink.finish()

        #expect(abs(duration - 11) < 0.05, "duration \(duration)")
        let audio = try samples(of: url)
        #expect(audio[0..<(48_000 * 9)].allSatisfy { $0 == 0 })
        #expect(audio[(48_000 * 10)...].contains { abs($0) > 0.3 })
    }

    @Test("Paused time is not filled with silence")
    func pauseShiftsTimeline() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = try AudioFileSink(fileURL: folder.appending(path: "mic.caf"), usesTimeline: true)
        let origin = mach_absolute_time()
        sink.startTimeline(at: origin)

        sink.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 1), hostTime: origin)
        sink.pauseTimeline(at: hostTime(origin, plus: 1))
        // Buffers during the pause are dropped.
        sink.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 1), hostTime: hostTime(origin, plus: 2))
        sink.resumeTimeline(at: hostTime(origin, plus: 5))
        sink.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 1), hostTime: hostTime(origin, plus: 5))

        #expect(abs(sink.finish() - 2) < 0.05)
    }

    @Test("Nothing is written before the timeline starts")
    func beforeStart() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = try AudioFileSink(fileURL: folder.appending(path: "early.caf"), usesTimeline: true)
        sink.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 1), hostTime: mach_absolute_time())
        #expect(sink.finish() == 0)
    }

    @Test("Small clock jitter doesn't insert silence")
    func jitterTolerance() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = try AudioFileSink(fileURL: folder.appending(path: "jitter.caf"), usesTimeline: true)
        let origin = mach_absolute_time()
        sink.startTimeline(at: origin)
        for index in 0..<10 {
            // 100 ms buffers arriving 30 ms late each.
            sink.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 0.1),
                        hostTime: hostTime(origin, plus: Double(index) * 0.1 + 0.03))
        }
        #expect(abs(sink.finish() - 1) < 0.01)
    }
}
