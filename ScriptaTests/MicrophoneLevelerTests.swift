import AVFoundation
import Foundation
import Testing
@testable import Scripta

@Suite("Microphone levelling")
struct MicrophoneLevelerTests {
    let root = TestAudio.temporaryDirectory()

    // MARK: - Helpers

    /// Speech stand-in: 400 ms tone bursts at `speechDecibels` RMS, separated
    /// by 300 ms of a quiet hum at `noiseDecibels`. Blocks of 50 ms line up
    /// with the bursts, so every speech block has exactly the given level.
    private static func speechLike(
        sampleRate: Double, duration: TimeInterval, speechDecibels: Float, noiseDecibels: Float = -65
    ) -> [Float] {
        let speechAmplitude: Float = pow(10, speechDecibels / 20) * Float(2).squareRoot()
        let noiseAmplitude: Float = pow(10, noiseDecibels / 20) * Float(2).squareRoot()
        return (0..<Int(sampleRate * duration)).map { index in
            let time = Double(index) / sampleRate
            let isSpeech = time.truncatingRemainder(dividingBy: 0.7) < 0.4
            let amplitude = isSpeech ? speechAmplitude : noiseAmplitude
            return amplitude * Float(sin(2 * .pi * (isSpeech ? 440 : 1_000) * time))
        }
    }

    private func write(_ samples: [Float], to url: URL) throws {
        let file = try AVAudioFile(
            forWriting: url, settings: CaptureFormat.fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false
        )
        let buffer = AVAudioPCMBuffer(pcmFormat: CaptureFormat.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    private func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// RMS in dBFS of the first burst (50–350 ms, away from its edges).
    private static func burstDecibels(_ samples: [Float], sampleRate: Double) -> Float {
        let burst = samples[Int(sampleRate * 0.05)..<Int(sampleRate * 0.35)]
        let rms = (burst.reduce(0) { $0 + $1 * $1 } / Float(burst.count)).squareRoot()
        return 20 * log10(rms)
    }

    // MARK: - Gain

    @Test("Quiet speech is raised to the target; loud speech and steady noise are left alone")
    func gainDecision() {
        let noise = [Float](repeating: -65, count: 60)
        #expect(MicrophoneLeveler.gainDecibels(forBlockDecibels: noise + [Float](repeating: -32, count: 40)) == 14)
        #expect(MicrophoneLeveler.gainDecibels(forBlockDecibels: noise + [Float](repeating: -17, count: 40)) == nil)
        #expect(MicrophoneLeveler.gainDecibels(forBlockDecibels: noise) == nil)
        // Digital silence doesn't count as a noise floor, and too little speech isn't trusted.
        #expect(MicrophoneLeveler.gainDecibels(forBlockDecibels: [Float](repeating: -120, count: 200)) == nil)
        #expect(MicrophoneLeveler.gainDecibels(forBlockDecibels: noise + [Float](repeating: -32, count: 5)) == nil)
    }

    @Test("The boost is capped, so a near-silent recording doesn't become loud noise")
    func gainIsCapped() {
        let blocks = [Float](repeating: -69, count: 60) + [Float](repeating: -50, count: 40)
        #expect(MicrophoneLeveler.gainDecibels(forBlockDecibels: blocks) == MicrophoneLeveler.maximumGainDecibels)
    }

    // MARK: - Files

    @Test("A quiet recording file is levelled in place to normal speech level")
    func levelsFile() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: CaptureFormat.fileName)
        try write(Self.speechLike(sampleRate: 48_000, duration: 5, speechDecibels: -32), to: url)

        let gain = try #require(try await MicrophoneLeveler.levelFile(at: url))

        #expect(abs(gain - 14) < 0.5, "gain \(gain)")
        let samples = try read(url)
        #expect(samples.count == 5 * 48_000)
        let level = Self.burstDecibels(samples, sampleRate: 48_000)
        #expect(abs(level - MicrophoneLeveler.targetDecibels) < 0.5, "level \(level)")
        // No temporary file is left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == [CaptureFormat.fileName])
    }

    @Test("Peaks are limited below -1 dBFS while speech gets the full boost")
    func limitsPeaks() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: CaptureFormat.fileName)
        var samples = Self.speechLike(sampleRate: 48_000, duration: 5, speechDecibels: -40)
        samples[Int(48_000 * 0.5)] = 0.6 // a bump against the microphone, in a pause
        try write(samples, to: url)

        try await MicrophoneLeveler.levelFile(at: url)

        let levelled = try read(url)
        let peak = levelled.map { abs($0) }.max() ?? 0
        #expect(peak <= PeakLimiter.ceiling + 0.0001, "peak \(peak)")
        let level = Self.burstDecibels(levelled, sampleRate: 48_000)
        #expect(abs(level - MicrophoneLeveler.targetDecibels) < 0.5, "level \(level)")
    }

    @Test("A recording that is already loud enough is not rewritten")
    func leavesLoudFileAlone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: CaptureFormat.fileName)
        try write(Self.speechLike(sampleRate: 48_000, duration: 3, speechDecibels: -16), to: url)
        let before = try Data(contentsOf: url)

        let gain = try await MicrophoneLeveler.levelFile(at: url)

        #expect(gain == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("Finishing a meeting levels only the microphone track, and only when enabled")
    func finisherLevelsMicrophoneTrack() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = RecordingStorage(rootURL: root)

        for levels in [true, false] {
            let manifest = RecordingManifest(
                id: UUID(), title: "Weekly", createdAt: .now, source: .meeting, fileName: CaptureFormat.mixFileName,
                microphoneFileName: CaptureFormat.microphoneFileName, systemFileName: CaptureFormat.systemFileName
            )
            try storage.makeFolder(for: manifest.id)
            let microphone = storage.fileURL(for: manifest.id, fileName: CaptureFormat.microphoneFileName)
            let system = storage.fileURL(for: manifest.id, fileName: CaptureFormat.systemFileName)
            try write(Self.speechLike(sampleRate: 48_000, duration: 3, speechDecibels: -32), to: microphone)
            try write(Self.speechLike(sampleRate: 48_000, duration: 3, speechDecibels: -30), to: system)

            let duration = try await RecordingFinisher.finish(manifest, storage: storage, levelsMicrophone: levels)

            #expect(abs(duration - 3) < 0.01)
            let microphoneLevel = Self.burstDecibels(try read(microphone), sampleRate: 48_000)
            let expected: Float = levels ? MicrophoneLeveler.targetDecibels : -32
            #expect(abs(microphoneLevel - expected) < 0.5, "levels \(levels): \(microphoneLevel)")
            // "Andere" stays as it was recorded.
            #expect(abs(Self.burstDecibels(try read(system), sampleRate: 48_000) + 30) < 0.5)
            #expect(FileManager.default.fileExists(atPath: storage.fileURL(for: manifest.id, fileName: CaptureFormat.mixFileName).path(percentEncoded: false)))
        }
    }

    // MARK: - Dictation

    @Test("Dictation samples in memory are levelled too")
    func levelsSamples() {
        var samples = Self.speechLike(sampleRate: 16_000, duration: 2, speechDecibels: -35)

        let gain = MicrophoneLeveler.level(&samples, sampleRate: 16_000)

        #expect(abs((gain ?? 0) - 17) < 0.5, "gain \(String(describing: gain))")
        let level = Self.burstDecibels(samples, sampleRate: 16_000)
        #expect(abs(level - MicrophoneLeveler.targetDecibels) < 0.5, "level \(level)")
    }
}
