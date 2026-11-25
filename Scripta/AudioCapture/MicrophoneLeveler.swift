import Accelerate
import AVFoundation
import os

/// Raises quiet microphone recordings to a normal speech level.
///
/// Some headsets deliver speech 15–20 dB below other sources even at full
/// input volume; meeting apps hide this with their own gain control. The
/// leveler measures how loud the speech is, applies one fixed gain to the
/// whole recording (so its dynamics stay as they are) and limits the few
/// peaks that would then clip. Recordings that are loud enough stay untouched.
enum MicrophoneLeveler {
    /// Speech level to reach: the 90th percentile of the 50 ms blocks that
    /// carry speech, in dBFS RMS. Meeting participants in system audio land
    /// around here.
    static let targetDecibels: Float = -18
    /// Upper bound, so a recording without real speech doesn't turn into loud noise.
    static let maximumGainDecibels: Float = 24
    /// Smaller corrections aren't worth rewriting the file.
    static let minimumGainDecibels: Float = 1.5
    /// Blocks this far above the noise floor count as speech.
    static let speechAboveFloorDecibels: Float = 12
    /// At least this much speech (50 ms blocks, i.e. 0.5 s) before the level is trusted.
    static let minimumSpeechBlocks = 10
    /// Blocks below this are digital silence (e.g. gaps on the timeline).
    static let silenceDecibels: Float = -70

    /// Gain in dB that brings the speech in `blockDecibels` (RMS of 50 ms
    /// blocks) to the target, or nil when no correction is needed or possible.
    static func gainDecibels(forBlockDecibels blockDecibels: [Float]) -> Float? {
        speechDecibels(forBlockDecibels: blockDecibels).flatMap(gainDecibels(forSpeechDecibels:))
    }

    /// How loud the speech in `blockDecibels` is (90th percentile of the
    /// blocks that carry speech), or nil when there isn't enough speech.
    static func speechDecibels(forBlockDecibels blockDecibels: [Float]) -> Float? {
        let audible = blockDecibels.filter { $0 > silenceDecibels }.sorted()
        guard audible.count >= minimumSpeechBlocks else { return nil }
        let noiseFloor = audible[audible.count / 10]
        // Still sorted, so the percentile is a plain index.
        let speech = audible.filter { $0 >= noiseFloor + speechAboveFloorDecibels }
        guard speech.count >= minimumSpeechBlocks else { return nil }
        return speech[speech.count * 9 / 10]
    }

    /// How loud the speech in mono `samples` is, or nil without enough speech.
    static func speechDecibels(of samples: [Float], sampleRate: Double) -> Float? {
        guard !samples.isEmpty else { return nil }
        var meter = LevelAccumulator(blockFrames: Int(sampleRate * 0.05))
        let decibels = samples.withUnsafeBufferPointer { meter.add($0.baseAddress!, count: $0.count) }
        return speechDecibels(forBlockDecibels: decibels)
    }

    /// Gain that brings speech at `speechLevel` to the target, or nil when
    /// the correction is too small to be worth it.
    static func gainDecibels(forSpeechDecibels speechLevel: Float) -> Float? {
        let gain = min(targetDecibels - speechLevel, maximumGainDecibels)
        return gain >= minimumGainDecibels ? gain : nil
    }

    // MARK: - Samples in memory (dictation)

    /// Levels mono samples in place. Returns the applied gain in dB, or nil.
    @discardableResult
    static func level(_ samples: inout [Float], sampleRate: Double) -> Float? {
        guard let speech = speechDecibels(of: samples, sampleRate: sampleRate),
              let gain = gainDecibels(forSpeechDecibels: speech) else { return nil }
        var limiter = PeakLimiter(gainDecibels: gain, sampleRate: sampleRate)
        samples.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, count: $0.count) }
        return gain
    }

    // MARK: - Captured files

    /// Levels a captured PCM file (.caf) in place, off the main actor. The
    /// levelled audio is written next to it and swapped in atomically, so the
    /// original survives a crash. Returns the applied gain in dB, or nil if
    /// the file stayed as it was.
    @discardableResult
    static func levelFile(at url: URL) async throws -> Float? {
        guard url.pathExtension == "caf",
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }

        let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        guard format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else {
            return nil
        }

        // Pass 1: how loud is the speech?
        var meter = LevelAccumulator(blockFrames: Int(format.sampleRate * 0.05))
        var decibels: [Float] = []
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            decibels += meter.decibels(of: buffer)
        }
        guard let gain = gainDecibels(forBlockDecibels: decibels) else { return nil }

        // Pass 2: write the levelled copy.
        let temporary = url.deletingLastPathComponent().appending(path: "levelling-\(UUID().uuidString).caf")
        do {
            input.framePosition = 0
            let output = try AVAudioFile(
                forWriting: temporary, settings: input.fileFormat.settings,
                commonFormat: .pcmFormatFloat32, interleaved: false
            )
            var limiter = PeakLimiter(gainDecibels: gain, sampleRate: format.sampleRate)
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                limiter.process(buffer.floatChannelData![0], count: Int(buffer.frameLength))
                try output.write(from: buffer)
            }
            output.close()
            // rename(2) replaces the original in one step.
            guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        Logger.recording.info("Levelled \(url.lastPathComponent, privacy: .public) by \(gain, format: .fixed(precision: 1)) dB")
        return gain
    }
}

/// Applies a fixed gain and keeps every sample below `ceiling`: instant
/// attack, about 100 ms release. Keeps its state across buffers.
struct PeakLimiter {
    /// -1 dBFS, headroom for the AAC encoder.
    static let ceiling: Float = 0.891

    private let gain: Float
    private let release: Float
    private var envelope: Float = 0

    init(gainDecibels: Float, sampleRate: Double) {
        gain = pow(10, gainDecibels / 20)
        release = Float(exp(-1 / (0.1 * sampleRate)))
    }

    mutating func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        var gain = gain
        vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(count))
        var envelope = envelope
        for index in 0..<count {
            envelope = max(abs(samples[index]), envelope * release)
            // The envelope is never below the current sample, so this lands at or under the ceiling.
            if envelope > Self.ceiling {
                samples[index] *= Self.ceiling / envelope
            }
        }
        self.envelope = envelope
    }
}
