import AVFoundation
import os

/// Encodes finished PCM recordings to AAC.
enum AudioEncoder {
    /// Encodes `source` as AAC into `destination` (.m4a). Runs off the main
    /// actor, reads one second at a time and writes to a temporary file that is
    /// moved into place only when complete.
    static func encodeAAC(source: URL, destination: URL, bitRate: Int) async throws {
        let temporary = destination.deletingLastPathComponent()
            .appending(path: "encoding-\(UUID().uuidString).m4a")
        do {
            let input = try AVAudioFile(forReading: source)
            let format = input.processingFormat
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: bitRate,
            ]
            let output = try AVAudioFile(
                forWriting: temporary, settings: settings,
                commonFormat: .pcmFormatFloat32, interleaved: false
            )
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else {
                throw CaptureSinkError.unsupportedFormat
            }
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
            output.close()

            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

/// Reads basic information from audio files.
enum AudioFileInfo {
    /// Duration in seconds, or nil if the file can't be read.
    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
