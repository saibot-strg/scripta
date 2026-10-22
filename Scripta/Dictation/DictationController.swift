import AVFAudio
import Foundation
import os

/// System-wide push-to-talk dictation: global shortcut → microphone into
/// memory → Parakeet → text into the focused app.
@MainActor
@Observable
final class DictationController {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Record while the shortcut is held.
        case hold
        /// Press to start, press again to stop.
        case toggle

        var id: String { rawValue }

        var label: LocalizedStringResource {
            switch self {
            case .hold: "Gedrückt halten"
            case .toggle: "Ein-/Ausschalten"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case finished(TextInserter.Result)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Recent microphone levels for the HUD.
    private(set) var levels: [Float] = []
    /// Set when the shortcut can't be registered (taken by another app).
    private(set) var registrationError: String?
    /// Key release → text inserted, of the last dictation.
    private(set) var lastLatency: Duration?

    private let transcription: TranscriptionService
    private let hotKeys = HotKeyCenter()
    private let inserter = TextInserter()
    private let hud = DictationHUD()
    private var capture: MicrophoneCapture?
    private var buffer: DictationAudioBuffer?
    private var levelTask: Task<Void, Never>?
    private var job: Task<Void, Never>?

    private static let shortcutID: UInt32 = 1
    private static let cancelID: UInt32 = 2
    /// Keeps recording briefly after release so the last syllable isn't cut.
    private static let releaseTail: Duration = .milliseconds(80)
    private static let minimumDuration: TimeInterval = 0.3

    init(transcription: TranscriptionService) {
        self.transcription = transcription
    }

    // MARK: - Settings

    /// Registers the shortcut and keeps the model loaded when dictation is on.
    func applySettings() {
        hotKeys.unregister(id: Self.shortcutID)
        registrationError = nil
        guard DictationSettings.isEnabled else {
            transcription.keepsModelLoaded = false
            return
        }
        do {
            try hotKeys.register(
                DictationSettings.shortcut, id: Self.shortcutID,
                onPress: { [weak self] in self?.shortcutPressed() },
                onRelease: { [weak self] in self?.shortcutReleased() }
            )
        } catch {
            registrationError = error.localizedDescription
        }
        transcription.keepsModelLoaded = true
        // Load now, so the first dictation is instant.
        Task { try? await transcription.prepareModel() }
    }

    /// While the settings record a new shortcut, the old one must not fire.
    func setShortcutSuspended(_ suspended: Bool) {
        if suspended {
            hotKeys.unregister(id: Self.shortcutID)
        } else {
            applySettings()
        }
    }

    // MARK: - Shortcut

    private func shortcutPressed() {
        switch DictationSettings.mode {
        case .hold:
            if phase != .recording { start() }
        case .toggle:
            phase == .recording ? finish() : start()
        }
    }

    private func shortcutReleased() {
        if DictationSettings.mode == .hold, phase == .recording {
            finish()
        }
    }

    // MARK: - Flow

    func start() {
        guard phase != .recording, phase != .transcribing else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .undetermined:
            Task { _ = await AVAudioApplication.requestRecordPermission() }
            return
        default:
            show(.failed(String(localized: "Kein Zugriff auf das Mikrofon")))
            return
        }

        let buffer = DictationAudioBuffer()
        let capture = MicrophoneCapture()
        self.buffer = buffer
        self.capture = capture
        levels = []
        phase = .recording
        hud.show(self)
        try? hotKeys.register(.escape, id: Self.cancelID, onPress: { [weak self] in self?.cancel() })

        levelTask = Task { [weak self] in
            for await newLevels in buffer.levels {
                guard let self else { return }
                levels.append(contentsOf: newLevels)
                if levels.count > 60 { levels.removeFirst(levels.count - 60) }
            }
        }
        Task {
            do {
                try await capture.start(delivering: buffer)
            } catch {
                cleanUpCapture()
                show(.failed(error.localizedDescription))
            }
        }
    }

    func finish() {
        guard phase == .recording, let capture, let buffer else { return }
        let releasedAt = ContinuousClock.now
        phase = .transcribing

        job = Task {
            defer { hotKeys.unregister(id: Self.cancelID) }
            try? await Task.sleep(for: Self.releaseTail)
            capture.stop()
            var samples = buffer.finish()
            cleanUpCapture()

            let duration = Double(samples.count) / DictationAudioBuffer.sampleRate
            guard duration >= Self.minimumDuration else {
                // A tap, not a dictation.
                phase = .idle
                hud.hide()
                return
            }
            if RecordingSettings.levelsMicrophone {
                MicrophoneLeveler.level(&samples, sampleRate: DictationAudioBuffer.sampleRate)
            }

            do {
                let text = try await transcription.dictate(samples: samples)
                let recognizedAt = ContinuousClock.now
                guard !Task.isCancelled else { return }
                let output = Self.format(text)
                guard !output.isEmpty else {
                    show(.failed(String(localized: "Nichts erkannt")))
                    return
                }
                let result = await inserter.insert(output)
                let latency = releasedAt.duration(to: .now)
                lastLatency = latency
                Logger.dictation.notice("""
                    Dictation: \(duration, format: .fixed(precision: 1)) s audio, \
                    recognition \(releasedAt.duration(to: recognizedAt).milliseconds) ms, \
                    total \(latency.milliseconds) ms (\(String(describing: result), privacy: .public))
                    """)
                show(.finished(result))
            } catch {
                show(.failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            }
        }
    }

    /// Esc while dictating: discard everything.
    func cancel() {
        hotKeys.unregister(id: Self.cancelID)
        job?.cancel()
        capture?.stop()
        _ = buffer?.finish()
        cleanUpCapture()
        phase = .idle
        hud.hide()
    }

    private func cleanUpCapture() {
        levelTask?.cancel()
        levelTask = nil
        capture = nil
        buffer = nil
    }

    /// Shows a final state in the HUD, then fades out.
    private func show(_ newPhase: Phase) {
        phase = newPhase
        hud.show(self)
        let delay: Duration = switch newPhase {
        case .finished(.inserted), .finished(.pasted): .milliseconds(600)
        default: .seconds(3)
        }
        hud.hide(after: delay) { [weak self] in
            guard let self, self.phase == newPhase else { return }
            self.phase = .idle
        }
    }

    nonisolated static func format(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return DictationSettings.appendsSpace ? trimmed + " " : trimmed
    }
}

private extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
    }
}

extension KeyShortcut {
    static let escape = KeyShortcut(keyCode: 53, carbonModifiers: 0)
}

/// Dictation preferences (UserDefaults).
enum DictationSettings {
    static let enabledKey = "dictation.enabled"
    static let modeKey = "dictation.mode"
    static let shortcutKey = "dictation.shortcut"
    static let appendsSpaceKey = "dictation.appendsSpace"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var mode: DictationController.Mode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(DictationController.Mode.init) ?? .hold
    }

    static var shortcut: KeyShortcut {
        get { KeyShortcut.load(forKey: shortcutKey) ?? .defaultDictation }
        set { newValue.save(forKey: shortcutKey) }
    }

    static var appendsSpace: Bool {
        UserDefaults.standard.object(forKey: appendsSpaceKey) as? Bool ?? true
    }
}
