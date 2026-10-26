import Foundation
import os

/// A stopped recording whose files are closed but not yet in the library.
struct FinishedRecording: Sendable {
    let manifest: RecordingManifest
    let duration: TimeInterval
    /// Where the files were written.
    let storage: RecordingStorage
    let rootBookmark: Data?
}

/// Storage location for a new recording.
struct RecordingLocation: Sendable {
    let storage: RecordingStorage
    let bookmark: Data?
}

/// Records the microphone, or a meeting (microphone + system audio as two
/// separate tracks), to disk and publishes live state for the UI.
///
/// The library entry is created by the caller after `stop()`. Until then the
/// recording folder holds a manifest, so an interrupted recording can be
/// recovered on the next launch (see `RecordingRecovery`).
@MainActor
@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle
        /// Starting inputs; for meetings this includes the system audio permission prompt.
        case starting
        case recording
        case paused
    }

    private(set) var state: State = .idle
    /// Recorded duration (pauses excluded), updated 20 times per second.
    private(set) var duration: TimeInterval = 0
    /// Whole seconds of `duration`: changes once per second, so timers and
    /// menus that only show seconds don't re-render 20 times per second.
    private(set) var elapsedSeconds = 0
    /// Recent microphone levels (0...1, newest last), 20 per second.
    private(set) var levels: [Float] = []
    /// Meeting only: recent system audio levels.
    private(set) var systemLevels: [Float] = []
    private(set) var title = ""
    private(set) var isMeeting = false
    /// Meeting only: apps are playing sound but nothing arrives — most likely
    /// the system audio permission is missing (Core Audio then delivers silence).
    private(set) var isSystemAudioMissing = false

    var isActive: Bool { state != .idle }
    /// ID of the recording in progress (also while starting).
    private(set) var activeRecordingID: UUID?

    /// Called when recording breaks off on its own (write error, input lost).
    var onFailure: ((RecordingError) -> Void)?

    #if DEBUG
    /// Records synthetic tones instead of the microphone and system audio.
    var usesTestTone = false
    #endif

    static let maxLevelCount = 160

    /// Asked at the start of each recording (the user may change the location).
    private let location: @MainActor () -> RecordingLocation
    private var session: Session?

    private struct Track {
        let role: TrackRole
        let sink: AudioFileSink
        let source: any AudioInputSource
        let events: Task<Void, Never>
    }

    private struct Session {
        let manifest: RecordingManifest
        let location: RecordingLocation
        let tracks: [Track]
        let activity: any NSObjectProtocol
        let monitor: Task<Void, Never>?
    }

    private struct Input {
        let role: TrackRole
        let fileName: String
        let source: any AudioInputSource
    }

    init(location: @escaping @MainActor () -> RecordingLocation) {
        self.location = location
    }

    /// Fixed location, for tests.
    convenience init(storage: RecordingStorage) {
        self.init(location: { RecordingLocation(storage: storage, bookmark: nil) })
    }

    // MARK: - Start

    func startMicrophone(title: String) async throws(RecordingError) {
        let manifest = RecordingManifest(
            id: UUID(), title: title, createdAt: .now, source: .microphone, fileName: CaptureFormat.fileName
        )
        try await start(manifest: manifest, inputs: [
            Input(role: .primary, fileName: CaptureFormat.fileName, source: makeMicrophone()),
        ])
    }

    func startMeeting(title: String, target: SystemAudioTarget) async throws(RecordingError) {
        let manifest = RecordingManifest(
            id: UUID(), title: title, createdAt: .now, source: .meeting, fileName: CaptureFormat.mixFileName,
            microphoneFileName: CaptureFormat.microphoneFileName, systemFileName: CaptureFormat.systemFileName
        )
        // System audio first: its permission prompt blocks until answered, and
        // starting the microphone afterwards keeps both tracks aligned.
        try await start(manifest: manifest, inputs: [
            Input(role: .system, fileName: CaptureFormat.systemFileName, source: makeSystemAudio(target)),
            Input(role: .microphone, fileName: CaptureFormat.microphoneFileName, source: makeMicrophone()),
        ])
    }

    private func start(manifest: RecordingManifest, inputs: [Input]) async throws(RecordingError) {
        guard state == .idle else { throw .alreadyRecording }
        state = .starting
        activeRecordingID = manifest.id
        title = manifest.title
        isMeeting = manifest.isMeeting
        isSystemAudioMissing = false
        duration = 0
        elapsedSeconds = 0
        levels = []
        systemLevels = []

        let location = location()
        let storage = location.storage
        var tracks: [Track] = []
        do {
            try storage.makeFolder(for: manifest.id)
            try storage.writeManifest(manifest)
            for input in inputs {
                let sink: AudioFileSink
                do {
                    sink = try AudioFileSink(fileURL: storage.fileURL(for: manifest.id, fileName: input.fileName), usesTimeline: true)
                } catch {
                    throw RecordingError.fileFailed(underlying: error)
                }
                do {
                    try await input.source.start(delivering: sink)
                } catch {
                    sink.finish()
                    throw error
                }
                let role = input.role
                let events = Task { [weak self] in
                    for await event in sink.events {
                        self?.handle(event, role: role)
                    }
                }
                tracks.append(Track(role: role, sink: sink, source: input.source, events: events))
            }
        } catch {
            for track in tracks {
                track.source.stop()
                track.sink.finish()
                track.events.cancel()
            }
            try? storage.removeFolder(for: manifest.id)
            state = .idle
            activeRecordingID = nil
            isMeeting = false
            throw (error as? RecordingError) ?? .fileFailed(underlying: error)
        }

        // All tracks share second zero from here on; earlier buffers (e.g. system
        // audio while the microphone was still starting) are dropped.
        let origin = mach_absolute_time()
        tracks.forEach { $0.sink.startTimeline(at: origin) }

        // Keep the Mac awake and out of App Nap while recording.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Recording audio"
        )
        session = Session(
            manifest: manifest, location: location, tracks: tracks, activity: activity,
            monitor: manifest.isMeeting ? monitorSystemAudio() : nil
        )
        state = .recording
        Logger.recording.info("Recording \(manifest.id, privacy: .public) started (meeting: \(manifest.isMeeting, privacy: .public))")
    }

    // MARK: - Pause, resume, stop

    func pause() {
        guard state == .recording, let session else { return }
        let now = mach_absolute_time()
        session.tracks.forEach {
            $0.sink.pauseTimeline(at: now)
            $0.source.pause()
        }
        state = .paused
    }

    func resume() async throws(RecordingError) {
        guard state == .paused, let session else { return }
        for track in session.tracks {
            try await track.source.resume()
        }
        let now = mach_absolute_time()
        session.tracks.forEach { $0.sink.resumeTimeline(at: now) }
        state = .recording
    }

    /// Moves the running recording to the microphone now chosen in the
    /// settings. The microphone track keeps its timeline, so it stays in sync
    /// with the system track.
    func switchMicrophone() throws(RecordingError) {
        guard let session else { return }
        for track in session.tracks where track.role != .system {
            try track.source.switchMicrophone()
        }
        Logger.recording.info("Recording \(session.manifest.id, privacy: .public) switched microphone")
    }

    /// Stops recording and closes all files.
    func stop() -> FinishedRecording? {
        guard let session else { return nil }
        var recordedDuration: TimeInterval = 0
        for track in session.tracks {
            track.source.stop()
            recordedDuration = max(recordedDuration, track.sink.finish())
            track.events.cancel()
        }
        session.monitor?.cancel()
        ProcessInfo.processInfo.endActivity(session.activity)
        self.session = nil
        state = .idle
        activeRecordingID = nil
        isMeeting = false
        isSystemAudioMissing = false
        levels = []
        systemLevels = []
        duration = 0
        elapsedSeconds = 0
        Logger.recording.info("Recording \(session.manifest.id, privacy: .public) stopped after \(recordedDuration, format: .fixed(precision: 1)) s")
        return FinishedRecording(
            manifest: session.manifest, duration: recordedDuration,
            storage: session.location.storage, rootBookmark: session.location.bookmark
        )
    }

    // MARK: - Events

    private func handle(_ event: CaptureEvent, role: TrackRole) {
        switch event {
        case .progress(let newLevels, let newDuration):
            if role == .system {
                Self.append(newLevels, to: &systemLevels)
                if newLevels.contains(where: { $0 > 0 }) { isSystemAudioMissing = false }
            } else {
                duration = newDuration
                let seconds = Int(newDuration)
                if seconds != elapsedSeconds { elapsedSeconds = seconds }
                Self.append(newLevels, to: &levels)
            }
        case .failed(let message):
            Logger.recording.error("Writing failed: \(message, privacy: .public)")
            onFailure?(.writeFailed(message: message))
        }
    }

    private static func append(_ newLevels: [Float], to levels: inout [Float]) {
        levels.append(contentsOf: newLevels)
        if levels.count > maxLevelCount {
            levels.removeFirst(levels.count - maxLevelCount)
        }
    }

    /// Without permission, Core Audio delivers digital silence instead of an
    /// error. Flag that case when other apps are audibly playing.
    private func monitorSystemAudio() -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            while !Task.isCancelled {
                guard let self else { return }
                let hasSignal = systemLevels.contains { $0 > 0 }
                if hasSignal { return }
                if state == .recording {
                    isSystemAudioMissing = AudioAppCatalog.isOtherAudioPlaying()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Sources

    private func makeMicrophone() -> any AudioInputSource {
        #if DEBUG
        if usesTestTone { return TestToneSource(frequency: 220) }
        #endif
        let capture = MicrophoneCapture()
        capture.onFailure = { [weak self] error in self?.onFailure?(error) }
        return capture
    }

    private func makeSystemAudio(_ target: SystemAudioTarget) -> any AudioInputSource {
        #if DEBUG
        if usesTestTone { return TestToneSource(frequency: 440) }
        #endif
        return SystemAudioCapture(target: target)
    }
}
