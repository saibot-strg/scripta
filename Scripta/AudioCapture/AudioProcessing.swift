import Accelerate
import AVFoundation

/// Receives audio buffers from a capture source (microphone, process tap, test
/// tone). Called on audio threads, hence `Sendable`.
protocol AudioBufferReceiver: Sendable {
    /// - Parameter hostTime: When the buffer's first sample was captured
    ///   (`mach_absolute_time` units), if the source knows it.
    func append(_ buffer: AVAudioPCMBuffer, hostTime: UInt64?)
}

extension AudioBufferReceiver {
    func append(_ buffer: AVAudioPCMBuffer) {
        append(buffer, hostTime: nil)
    }
}

/// Converts a stream of buffers in any format to one target format, keeping
/// resampler state between buffers. Not thread-safe; owners serialize access.
struct StreamConverter {
    let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    mutating func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == targetFormat { return buffer }

        // Input devices can change mid-recording (e.g. a headset); rebuild the converter then.
        if converter?.inputFormat != buffer.format {
            guard let newConverter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
                throw CaptureSinkError.unsupportedFormat
            }
            newConverter.downmix = true
            converter = newConverter
        }
        guard let converter else { throw CaptureSinkError.unsupportedFormat }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw CaptureSinkError.unsupportedFormat
        }

        let input = ConverterInput(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError, withInputFrom: input.provide)
        if status == .error {
            throw conversionError ?? CaptureSinkError.conversionFailed
        }
        return output
    }
}

/// Turns mono samples into meter levels, one per block (e.g. 50 ms).
struct LevelAccumulator {
    let blockFrames: Int
    private var sumOfSquares: Float = 0
    private var frameCount = 0

    init(blockFrames: Int) {
        self.blockFrames = blockFrames
    }

    mutating func levels(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let samples = buffer.floatChannelData?[0] else { return [] }
        let count = Int(buffer.frameLength)
        var levels: [Float] = []
        var index = 0
        while index < count {
            let take = min(blockFrames - frameCount, count - index)
            var sum: Float = 0
            vDSP_svesq(samples + index, 1, &sum, vDSP_Length(take))
            sumOfSquares += sum
            frameCount += take
            index += take
            if frameCount == blockFrames {
                levels.append(LevelMeter.normalizedLevel(rms: (sumOfSquares / Float(blockFrames)).squareRoot()))
                sumOfSquares = 0
                frameCount = 0
            }
        }
        return levels
    }
}

/// Hands one buffer to `AVAudioConverter`, then reports "no data for now" so
/// the converter keeps its resampler state for the next buffer.
private final class ConverterInput {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(_ packetCount: AVAudioPacketCount, _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}

enum CaptureSinkError: LocalizedError {
    case unsupportedFormat
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: String(localized: "Das Audioformat des Eingangs wird nicht unterstützt.")
        case .conversionFailed: String(localized: "Das Audiosignal konnte nicht umgewandelt werden.")
        }
    }
}
