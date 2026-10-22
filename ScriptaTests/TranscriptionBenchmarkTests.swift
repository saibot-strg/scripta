import AVFoundation
import Darwin
import Foundation
import Synchronization
import Testing
@testable import Scripta

/// 60-minute transcription and diarization benchmarks. Opt-in because they take a while:
///
///     TEST_RUNNER_SCRIPTA_BENCHMARK=1 xcodebuild test -only-testing:ScriptaTests/TranscriptionBenchmarkTests …
@Suite(
    "Transcription benchmark",
    .enabled(if: ProcessInfo.processInfo.environment["SCRIPTA_BENCHMARK"] == "1" && ParakeetEngine.isModelInstalled)
)
struct TranscriptionBenchmarkTests {
    @Test("60 minutes of speech: completes, timings cover the file, memory stays bounded")
    func sixtyMinutes() async throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "60min.caf")
        let duration = try makeLongFile(at: url, minutes: 60)

        let engine = ParakeetEngine()
        try await engine.prepare { _ in }
        let memoryBefore = residentMemory()
        let peak = PeakMemory()
        let sampler = Task {
            while !Task.isCancelled {
                peak.record(residentMemory())
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        let clock = ContinuousClock()
        let start = clock.now
        let result = try await engine.transcribe(fileURL: url) { _ in }
        let elapsed = start.duration(to: clock.now)
        sampler.cancel()

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let growthMB = Double(peak.value - memoryBefore) / 1_048_576
        let report = String(
            format: "60 min audio in %.1f s (%.0fx real time), %d words, peak memory growth %.0f MB",
            seconds, duration / seconds, result.words.count, growthMB
        )
        print("BENCHMARK \(report)")

        #expect(result.words.count > 5_000)
        #expect((result.words.last?.end ?? 0) > duration - 30)
        #expect(growthMB < 1_500, "memory grew by \(growthMB) MB")
    }

    @Test("60 minutes of a dialogue: speakers are separated quickly", .enabled(if: SpeakerDiarizer.isModelInstalled))
    func sixtyMinutesDiarization() async throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "60min-dialogue.caf")
        let duration = try makeLongFile(at: url, minutes: 60, resource: "speakers-en")

        let diarizer = SpeakerDiarizer()
        try await diarizer.prepare { _ in }
        let memoryBefore = residentMemory()
        let peak = PeakMemory()
        let sampler = Task {
            while !Task.isCancelled {
                peak.record(residentMemory())
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        let clock = ContinuousClock()
        let start = clock.now
        let result = try await diarizer.diarize(fileURL: url) { _ in }
        let elapsed = start.duration(to: clock.now)
        sampler.cancel()

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let growthMB = Double(peak.value - memoryBefore) / 1_048_576
        let report = String(
            format: "60 min dialogue diarized in %.1f s (%.0fx real time), %d speakers, %d turns, peak memory growth %.0f MB",
            seconds, duration / seconds, result.speakers.count, result.turns.count, growthMB
        )
        print("BENCHMARK \(report)")

        #expect(result.speakers.count == 2, "\(result.speakers)")
        #expect(seconds < 120)
        #expect(growthMB < 1_500, "memory grew by \(growthMB) MB")
    }

    /// Repeats a test recording into one long PCM file (16 kHz mono).
    private func makeLongFile(at url: URL, minutes: Double, resource: String = "speech-de") throws -> TimeInterval {
        let source = try AVAudioFile(forReading: Bundle(for: Token.self).url(forResource: resource, withExtension: "m4a")!)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let converter = AVAudioConverter(from: source.processingFormat, to: format)!
        let input = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length))!
        try source.read(into: input)
        let clip = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 16_000 / source.processingFormat.sampleRate) + 1_024)!
        var consumed = false
        _ = converter.convert(to: clip, error: nil) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }

        let output = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let clipDuration = Double(clip.frameLength) / 16_000
        let repeats = Int((minutes * 60 / clipDuration).rounded(.up))
        for _ in 0..<repeats { try output.write(from: clip) }
        return Double(repeats) * clipDuration
    }

    private func residentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

private final class Token {}

/// Thread-safe running maximum.
private final class PeakMemory: Sendable {
    private let peak = Mutex<UInt64>(0)

    func record(_ value: UInt64) {
        peak.withLock { $0 = max($0, value) }
    }

    var value: UInt64 { peak.withLock { $0 } }
}
