import Accelerate
import AVFoundation
import os

/// Mixes the separate meeting tracks into one file for playback.
enum AudioMixer {
    /// Sums mono capture files (48 kHz) into `output` and returns its duration.
    /// Missing or unreadable inputs are skipped; shorter inputs end in silence.
    /// Runs off the main actor and processes one second at a time.
    static func mix(_ inputs: [URL], into output: URL) async throws -> TimeInterval {
        let format = CaptureFormat.processingFormat
        let chunk = AVAudioFrameCount(CaptureFormat.sampleRate)
        let files = inputs.compactMap { try? AVAudioFile(forReading: $0, commonFormat: .pcmFormatFloat32, interleaved: false) }
            .filter { $0.processingFormat.sampleRate == format.sampleRate && $0.processingFormat.channelCount == 1 }
        guard !files.isEmpty,
              let mixed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
              let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw CaptureSinkError.unsupportedFormat
        }

        let temporary = output.deletingLastPathComponent().appending(path: "mixing-\(UUID().uuidString).caf")
        do {
            let writer = try AVAudioFile(
                forWriting: temporary, settings: CaptureFormat.fileSettings,
                commonFormat: .pcmFormatFloat32, interleaved: false
            )
            var totalFrames: AVAudioFramePosition = 0
            while true {
                try Task.checkCancellation()
                vDSP_vclr(mixed.floatChannelData![0], 1, vDSP_Length(chunk))
                var framesInChunk: AVAudioFrameCount = 0
                for file in files where file.framePosition < file.length {
                    try file.read(into: scratch, frameCount: chunk)
                    vDSP_vadd(mixed.floatChannelData![0], 1, scratch.floatChannelData![0], 1,
                              mixed.floatChannelData![0], 1, vDSP_Length(scratch.frameLength))
                    framesInChunk = max(framesInChunk, scratch.frameLength)
                }
                guard framesInChunk > 0 else { break }
                // Keep the sum in range; overlapping speech rarely clips, but never wraps.
                var low: Float = -1, high: Float = 1
                vDSP_vclip(mixed.floatChannelData![0], 1, &low, &high, mixed.floatChannelData![0], 1, vDSP_Length(framesInChunk))
                mixed.frameLength = framesInChunk
                try writer.write(from: mixed)
                totalFrames += AVAudioFramePosition(framesInChunk)
            }
            writer.close()
            if FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: output)
            }
            try FileManager.default.moveItem(at: temporary, to: output)
            return Double(totalFrames) / CaptureFormat.sampleRate
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

/// Turns the captured tracks of a stopped recording into its final files:
/// levels the microphone and, for meetings, mixes both tracks into the
/// playback file.
enum RecordingFinisher {
    /// Returns the duration of the playback file.
    /// - Parameter levelsMicrophone: Raise a quiet microphone track (setting).
    static func finish(
        _ manifest: RecordingManifest, storage: RecordingStorage,
        levelsMicrophone: Bool = RecordingSettings.levelsMicrophone
    ) async throws -> TimeInterval {
        if levelsMicrophone, let fileName = manifest.microphoneTrackFileName {
            do {
                try await MicrophoneLeveler.levelFile(at: storage.fileURL(for: manifest.id, fileName: fileName))
            } catch {
                // The unlevelled track is still fine to keep.
                Logger.recording.error("Levelling failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let output = storage.fileURL(for: manifest.id, fileName: manifest.fileName)
        guard manifest.isMeeting else {
            return AudioFileInfo.duration(of: output) ?? 0
        }
        let inputs = manifest.capturedFileNames.map { storage.fileURL(for: manifest.id, fileName: $0) }
        return try await AudioMixer.mix(inputs, into: output)
    }
}
