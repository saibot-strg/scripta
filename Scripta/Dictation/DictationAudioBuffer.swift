import AVFoundation
import Synchronization

/// Collects dictation audio in memory as 16 kHz mono Float32, the format
/// Parakeet expects, so short dictations never touch the disk.
final class DictationAudioBuffer: AudioBufferReceiver {
    static let sampleRate: Double = 16_000

    /// Meter levels for the HUD (0...1, one per 50 ms).
    let levels: AsyncStream<[Float]>
    private let continuation: AsyncStream<[Float]>.Continuation
    private let state: Mutex<State>

    private struct State {
        var converter: StreamConverter
        var meter: LevelAccumulator
        var samples: [Float] = []
        var isClosed = false
    }

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            preconditionFailure("16 kHz mono is always a valid format")
        }
        (levels, continuation) = AsyncStream.makeStream(of: [Float].self, bufferingPolicy: .bufferingNewest(32))
        var initial = State(
            converter: StreamConverter(targetFormat: format),
            meter: LevelAccumulator(blockFrames: Int(Self.sampleRate * 0.05))
        )
        // About 30 s up front; dictations are usually much shorter.
        initial.samples.reserveCapacity(Int(Self.sampleRate) * 30)
        state = Mutex(initial)
    }

    func append(_ buffer: AVAudioPCMBuffer, hostTime: UInt64?) {
        let newLevels: [Float]? = state.withLock { state in
            guard !state.isClosed,
                  let converted = try? state.converter.convert(buffer),
                  let channel = converted.floatChannelData?[0] else { return nil }
            state.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            return state.meter.levels(of: converted)
        }
        if let newLevels, !newLevels.isEmpty {
            continuation.yield(newLevels)
        }
    }

    /// Stops collecting and hands over the samples (the buffer is empty afterwards).
    func finish() -> [Float] {
        continuation.finish()
        return state.withLock { state in
            state.isClosed = true
            defer { state.samples = [] }
            return state.samples
        }
    }

    var duration: TimeInterval {
        state.withLock { Double($0.samples.count) / Self.sampleRate }
    }
}
