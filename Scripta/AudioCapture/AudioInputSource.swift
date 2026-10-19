import AVFoundation
import os

/// Something that delivers audio buffers to a receiver (file or memory).
@MainActor
protocol AudioInputSource: AnyObject {
    func start(delivering sink: any AudioBufferReceiver) async throws(RecordingError)
    func pause()
    func resume() async throws(RecordingError)
    func stop()
}

/// The default system microphone via `AVAudioEngine`.
@MainActor
final class MicrophoneCapture: AudioInputSource {
    /// Called when the input fails after a device change.
    var onFailure: ((RecordingError) -> Void)?

    private let engine = AVAudioEngine()
    private var sink: (any AudioBufferReceiver)?
    private var isPaused = false
    private var configurationObserver: (any NSObjectProtocol)?

    func start(delivering sink: any AudioBufferReceiver) async throws(RecordingError) {
        self.sink = sink
        selectInputDevice()
        try installTap()
        try startEngine()
        // The engine stops itself when the input device changes (e.g. AirPods connect).
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    func pause() {
        engine.pause()
        isPaused = true
    }

    func resume() async throws(RecordingError) {
        try startEngine()
        isPaused = false
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink = nil
    }

    /// Uses the microphone chosen in the settings; falls back to the system
    /// default when it isn't connected.
    private func selectInputDevice() {
        guard let deviceID = AudioInputDevices.selectedDeviceID() else { return }
        do {
            try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
        } catch {
            Logger.recording.error("Could not select microphone: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func installTap() throws(RecordingError) {
        guard let sink else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw .noInputDevice }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4_800, format: format, block: Self.tapBlock(for: sink))
    }

    private func startEngine() throws(RecordingError) {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw .engineFailed(underlying: error)
        }
    }

    /// Created outside the main actor on purpose: the tap runs on an audio thread.
    private nonisolated static func tapBlock(for sink: any AudioBufferReceiver) -> AVAudioNodeTapBlock {
        { buffer, time in
            sink.append(buffer, hostTime: time.isHostTimeValid ? time.hostTime : nil)
        }
    }

    private func handleConfigurationChange() {
        guard sink != nil else { return }
        Logger.recording.info("Audio configuration changed, reinstalling input tap")
        do {
            try installTap()
            if !isPaused {
                try startEngine()
            }
        } catch {
            onFailure?(error)
        }
    }
}

#if DEBUG
/// Synthetic 44.1 kHz stereo input for tests and UI work without a microphone
/// (debug builds only). Exercises the same conversion and file path.
@MainActor
final class TestToneSource: AudioInputSource {
    private let frequency: Double
    private var sink: (any AudioBufferReceiver)?
    private var task: Task<Void, Never>?

    init(frequency: Double = 220) {
        self.frequency = frequency
    }

    func start(delivering sink: any AudioBufferReceiver) async throws(RecordingError) {
        self.sink = sink
        startGenerating()
    }

    func pause() {
        task?.cancel()
        task = nil
    }

    func resume() async throws(RecordingError) {
        startGenerating()
    }

    func stop() {
        task?.cancel()
        task = nil
        sink = nil
    }

    private func startGenerating() {
        guard let sink else { return }
        let frequency = frequency
        task = Task.detached { await Self.generate(into: sink, frequency: frequency) }
    }

    private nonisolated static func generate(into sink: any AudioBufferReceiver, frequency: Double) async {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        var time = 0.0
        while !Task.isCancelled {
            let frames = AVAudioFrameCount(sampleRate / 10)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let channels = buffer.floatChannelData else { return }
            buffer.frameLength = frames
            for index in 0..<Int(frames) {
                // Tone with a slow "speech-like" swell.
                let envelope = 0.5 + 0.5 * sin(2 * .pi * 0.7 * time)
                let value = Float(0.4 * envelope * sin(2 * .pi * frequency * time))
                channels[0][index] = value
                channels[1][index] = value
                time += 1 / sampleRate
            }
            sink.append(buffer)
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
#endif
