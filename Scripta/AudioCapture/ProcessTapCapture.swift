import AVFAudio
import CoreAudio
import Synchronization
import os

/// Captures system or app audio through a Core Audio process tap and a private
/// aggregate device (macOS 14.2+).
///
/// All HAL work runs on a private queue: the first start shows the
/// "System Audio Recording" permission prompt and blocks until it is answered.
/// If the user declines, the tap delivers silence instead of an error.
final class ProcessTapCapture: Sendable {
    private let tapDescription: @Sendable () -> CATapDescription
    private let queue = DispatchQueue(label: "io.github.saibot-strg.Scripta.ProcessTap", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "io.github.saibot-strg.Scripta.ProcessTap.IO", qos: .userInteractive)
    private let state = Mutex(State())

    private struct State {
        var sink: (any AudioBufferReceiver)?
        var tap: AudioHardwareTap?
        var aggregate: AudioHardwareAggregateDevice?
        var ioProcID: AudioDeviceIOProcID?
        var outputListener: AudioObjectPropertyListenerBlock?
        var isPaused = false
    }

    /// - Parameter tapDescription: Builds a fresh description for every (re)build.
    init(tapDescription: @escaping @Sendable () -> CATapDescription) {
        self.tapDescription = tapDescription
    }

    func start(sink: any AudioBufferReceiver) async throws {
        try await perform {
            self.state.withLock { $0.sink = sink }
            try self.build()
            try self.startDevice()
            self.observeOutputDevice()
        }
    }

    func pause() {
        queue.async {
            self.state.withLock { $0.isPaused = true }
            try? self.stopDevice()
        }
    }

    func resume() async throws {
        try await perform {
            self.state.withLock { $0.isPaused = false }
            try self.startDevice()
        }
    }

    /// Stops capturing and releases the tap. Safe to call more than once.
    func invalidate() {
        queue.async {
            self.removeOutputObserver()
            self.teardown()
            self.state.withLock { $0.sink = nil }
        }
    }

    #if DEBUG
    /// Builds tap and aggregate without starting them (no permission prompt)
    /// and returns a description, for checking the HAL setup in debug builds.
    func probe(sink: any AudioBufferReceiver) async throws -> String {
        let result = Mutex("")
        try await perform {
            self.state.withLock { $0.sink = sink }
            try self.build()
            let (tap, aggregate) = self.state.withLock { ($0.tap, $0.aggregate) }
            let format = try tap?.format
            let text = "tap=\(tap?.id ?? 0) aggregate=\(aggregate?.id ?? 0) rate=\(format?.mSampleRate ?? 0) channels=\(format?.mChannelsPerFrame ?? 0)"
            result.withLock { $0 = text }
            self.teardown()
        }
        return result.withLock { $0 }
    }
    #endif

    // MARK: - Queue

    private func perform(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    self.teardown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - HAL objects (queue only)

    private func build() throws {
        guard let sink = state.withLock({ $0.sink }) else { return }
        let system = AudioHardwareSystem.shared
        let description = tapDescription()
        guard let tap = try system.makeProcessTap(description: description) else {
            throw AudioHardwareError(kAudioHardwareUnspecifiedError)
        }
        var streamDescription = try tap.format
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            try? system.destroyProcessTap(tap)
            throw CaptureSinkError.unsupportedFormat
        }

        // The aggregate contains only the tap (like Apple's sample). Adding the
        // output device as a sub-device would also add its input streams when
        // it is a headset with a microphone (e.g. USB headsets, AirPods).
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Scripta System Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: try tap.uid, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        guard let aggregate = try system.makeAggregateDevice(description: composition) else {
            try? system.destroyProcessTap(tap)
            throw AudioHardwareError(kAudioHardwareUnspecifiedError)
        }

        // The IO block owns the extractor; it is released with the IO proc.
        var ioProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggregate.id, ioQueue, Self.ioBlock(extractor: TapBufferExtractor(format: format), sink: sink)
        )
        guard status == noErr, let ioProcID else {
            try? system.destroyAggregateDevice(aggregate)
            try? system.destroyProcessTap(tap)
            throw AudioHardwareError(status)
        }
        state.withLock { state in
            state.tap = tap
            state.aggregate = aggregate
            state.ioProcID = ioProcID
        }
        Logger.recording.info("Process tap ready: \(format.sampleRate, format: .fixed(precision: 0)) Hz, \(format.channelCount) ch")
    }

    private func startDevice() throws {
        let (aggregate, ioProcID) = state.withLock { ($0.aggregate, $0.ioProcID) }
        guard let aggregate, let ioProcID else { return }
        try aggregate.start(IOProcID: ioProcID)
    }

    private func stopDevice() throws {
        let (aggregate, ioProcID) = state.withLock { ($0.aggregate, $0.ioProcID) }
        guard let aggregate, let ioProcID else { return }
        try aggregate.stop(IOProcID: ioProcID)
    }

    private func teardown() {
        let (tap, aggregate, ioProcID) = state.withLock { state in
            defer {
                state.tap = nil
                state.aggregate = nil
                state.ioProcID = nil
            }
            return (state.tap, state.aggregate, state.ioProcID)
        }
        let system = AudioHardwareSystem.shared
        if let aggregate {
            if let ioProcID {
                try? aggregate.stop(IOProcID: ioProcID)
                AudioDeviceDestroyIOProcID(aggregate.id, ioProcID)
            }
            try? system.destroyAggregateDevice(aggregate)
        }
        if let tap {
            try? system.destroyProcessTap(tap)
        }
    }

    // MARK: - Output device changes

    /// The tap's format is fixed at creation; when the output device changes
    /// (e.g. AirPods connect) the tap and aggregate are rebuilt. The file sink
    /// adapts to a new input format on its own.
    private func observeOutputDevice() {
        state.withLock { state in
            var address = PropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.rebuildAfterDeviceChange()
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener) == noErr {
                state.outputListener = listener
            }
        }
    }

    private func removeOutputObserver() {
        state.withLock { state in
            guard let listener = state.outputListener else { return }
            var address = PropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            state.outputListener = nil
        }
    }

    private func rebuildAfterDeviceChange() {
        guard state.withLock({ $0.sink != nil }) else { return }
        Logger.recording.info("Output device changed, rebuilding process tap")
        teardown()
        do {
            try build()
            if !state.withLock({ $0.isPaused }) {
                try startDevice()
            }
        } catch {
            Logger.recording.error("Rebuilding process tap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Created outside any actor: the block runs on the HAL's IO queue.
    private static func ioBlock(extractor: TapBufferExtractor, sink: any AudioBufferReceiver) -> AudioDeviceIOBlock {
        { _, inputData, inputTime, _, _ in
            guard let buffer = extractor.buffer(from: inputData) else { return }
            let time = inputTime.pointee
            let hostTime = time.mFlags.contains(.hostTimeValid) ? time.mHostTime : nil
            sink.append(buffer, hostTime: hostTime)
        }
    }
}

/// Wraps the tap's part of the aggregate device's input in an
/// `AVAudioPCMBuffer` without copying audio. Taps come after any device
/// streams, so if the input holds more buffers than the tap format describes,
/// the last ones belong to the tap. Used only on the IO queue.
final class TapBufferExtractor {
    let format: AVAudioFormat
    private let tapBufferCount: Int
    private let scratch: UnsafeMutableAudioBufferListPointer
    private var hasLoggedFirstBuffer = false
    private var hasLoggedMismatch = false

    init(format: AVAudioFormat) {
        self.format = format
        tapBufferCount = format.isInterleaved ? 1 : Int(format.channelCount)
        scratch = AudioBufferList.allocate(maximumBuffers: tapBufferCount)
    }

    deinit {
        free(scratch.unsafeMutablePointer)
    }

    func buffer(from input: UnsafePointer<AudioBufferList>) -> AVAudioPCMBuffer? {
        let available = Int(input.pointee.mNumberBuffers)
        let buffer: AVAudioPCMBuffer?
        if available == tapBufferCount {
            buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input)
        } else if available > tapBufferCount {
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            for index in 0..<tapBufferCount {
                scratch[index] = list[available - tapBufferCount + index]
            }
            buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: scratch.unsafePointer)
        } else {
            buffer = nil
        }

        if buffer == nil, !hasLoggedMismatch {
            hasLoggedMismatch = true
            Logger.recording.error("System audio buffer doesn't match the tap format (\(available) buffers, expected \(self.tapBufferCount))")
        } else if buffer != nil, !hasLoggedFirstBuffer {
            hasLoggedFirstBuffer = true
            Logger.recording.notice("System audio is arriving (\(available) buffers per cycle)")
        }
        return buffer
    }
}

/// `AudioInputSource` for system or app audio.
@MainActor
final class SystemAudioCapture: AudioInputSource {
    private let capture: ProcessTapCapture

    init(target: SystemAudioTarget) {
        // Resolve the processes now (main actor); the description itself is
        // rebuilt on the capture queue whenever the tap is recreated.
        let ownProcess = (try? AudioHardwareSystem.shared.process(for: ProcessInfo.processInfo.processIdentifier))?.id
        let members: (processes: [AudioObjectID], bundleIDs: [String])? = switch target {
        case .allSystemAudio: nil
        case .application(let app): AudioAppCatalog.tapMembers(for: app)
        }
        capture = ProcessTapCapture {
            let description: CATapDescription
            if let members {
                description = CATapDescription(stereoMixdownOfProcesses: members.processes)
                // Follow the app by bundle ID, also across relaunches of its processes.
                description.bundleIDs = members.bundleIDs
                description.isProcessRestoreEnabled = true
            } else {
                description = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcess.map { [$0] } ?? [])
            }
            description.name = "Scripta"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            return description
        }
    }

    func start(delivering sink: any AudioBufferReceiver) async throws(RecordingError) {
        do {
            try await capture.start(sink: sink)
        } catch {
            throw .systemAudioFailed(underlying: error)
        }
    }

    func pause() {
        capture.pause()
    }

    func resume() async throws(RecordingError) {
        do {
            try await capture.resume()
        } catch {
            throw .systemAudioFailed(underlying: error)
        }
    }

    func stop() {
        capture.invalidate()
    }

    #if DEBUG
    func probe(sink: any AudioBufferReceiver) async throws -> String {
        try await capture.probe(sink: sink)
    }
    #endif
}
