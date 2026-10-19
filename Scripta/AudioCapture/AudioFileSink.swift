import AVFoundation
import CoreAudio
import Synchronization

/// Messages from the capture thread to the UI.
enum CaptureEvent: Sendable {
    /// New meter levels (0...1, one per 50 ms) and the total recorded duration.
    case progress(levels: [Float], duration: TimeInterval)
    /// Writing failed; the file contains everything up to this point.
    case failed(message: String)
}

/// Receives audio buffers on the capture thread, converts them to the capture
/// format (48 kHz mono) and appends them to the CAF file immediately.
///
/// With a timeline (meetings and recordings), every buffer is placed by its
/// capture time: gaps are filled with silence. System audio only delivers
/// buffers while some app plays sound, so without this the "Andere" track
/// would lose all silent stretches and drift ahead of "Ich".
///
/// Thread-safe: `append` is called from audio threads, everything else from
/// the main actor. All mutable state lives behind a mutex.
final class AudioFileSink: AudioBufferReceiver {
    let fileURL: URL
    let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    private let state: Mutex<State>

    /// Frames per meter level (50 ms).
    static let levelBlockFrames = Int(CaptureFormat.sampleRate * 0.05)
    /// Gaps shorter than this are clock jitter, not silence.
    static let gapTolerance = AVAudioFramePosition(CaptureFormat.sampleRate * 0.1)

    private struct State {
        var file: AVAudioFile?
        var converter: StreamConverter
        var meter: LevelAccumulator
        var framesWritten: AVAudioFramePosition = 0
        var hasFailed = false
        /// Timeline mode: buffers before `origin` or while paused are dropped.
        let usesTimeline: Bool
        var origin: UInt64?
        var pausedAt: UInt64?
    }

    /// - Parameter usesTimeline: Place buffers by capture time (see type docs).
    ///   Nothing is written until `startTimeline(at:)`.
    init(fileURL: URL, usesTimeline: Bool = false) throws {
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: CaptureFormat.fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.fileURL = fileURL
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self, bufferingPolicy: .bufferingNewest(64))
        state = Mutex(State(
            file: file,
            converter: StreamConverter(targetFormat: CaptureFormat.processingFormat),
            meter: LevelAccumulator(blockFrames: Self.levelBlockFrames),
            usesTimeline: usesTimeline
        ))
    }

    // MARK: - Timeline

    /// Second zero of the recording; all tracks of a meeting share it.
    func startTimeline(at hostTime: UInt64) {
        state.withLock { $0.origin = hostTime }
    }

    func pauseTimeline(at hostTime: UInt64) {
        state.withLock { $0.pausedAt = hostTime }
    }

    /// Shifts the origin by the pause, so paused time isn't filled with silence.
    func resumeTimeline(at hostTime: UInt64) {
        state.withLock { state in
            guard let pausedAt = state.pausedAt, let origin = state.origin else { return }
            state.origin = origin + (hostTime - min(pausedAt, hostTime))
            state.pausedAt = nil
        }
    }

    // MARK: - Writing

    /// Converts and writes one buffer. Called on the capture thread.
    func append(_ buffer: AVAudioPCMBuffer, hostTime: UInt64?) {
        let event: CaptureEvent? = state.withLock { state in
            guard !state.hasFailed, let file = state.file else { return nil }
            do {
                if state.usesTimeline {
                    guard let origin = state.origin, state.pausedAt == nil else { return nil }
                    let captured = hostTime ?? mach_absolute_time()
                    guard captured >= origin else { return nil }
                    let expected = AVAudioFramePosition(
                        Double(AudioConvertHostTimeToNanos(captured - origin)) / 1e9 * CaptureFormat.sampleRate
                    )
                    let gap = expected - state.framesWritten
                    if gap > Self.gapTolerance {
                        try Self.writeSilence(frames: gap, to: file)
                        state.framesWritten += gap
                    }
                }
                let converted = try state.converter.convert(buffer)
                guard converted.frameLength > 0 else { return nil }
                try file.write(from: converted)
                state.framesWritten += AVAudioFramePosition(converted.frameLength)
                let levels = state.meter.levels(of: converted)
                return .progress(levels: levels, duration: Double(state.framesWritten) / CaptureFormat.sampleRate)
            } catch {
                state.hasFailed = true
                return .failed(message: error.localizedDescription)
            }
        }
        if let event {
            continuation.yield(event)
        }
    }

    private static func writeSilence(frames: AVAudioFramePosition, to file: AVAudioFile) throws {
        let chunk = AVAudioFrameCount(CaptureFormat.sampleRate)
        guard let silence = AVAudioPCMBuffer(pcmFormat: CaptureFormat.processingFormat, frameCapacity: chunk) else { return }
        silence.frameLength = chunk
        memset(silence.floatChannelData![0], 0, Int(chunk) * MemoryLayout<Float>.size)
        var remaining = frames
        while remaining > 0 {
            silence.frameLength = AVAudioFrameCount(min(remaining, AVAudioFramePosition(chunk)))
            try file.write(from: silence)
            remaining -= AVAudioFramePosition(silence.frameLength)
        }
    }

    /// Closes the file and returns the recorded duration in seconds.
    @discardableResult
    func finish() -> TimeInterval {
        let frames = state.withLock { state -> AVAudioFramePosition in
            state.file?.close()
            state.file = nil
            return state.framesWritten
        }
        continuation.finish()
        return Double(frames) / CaptureFormat.sampleRate
    }
}
