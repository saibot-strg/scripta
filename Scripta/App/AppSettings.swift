import AppKit
import Foundation

/// UserDefaults keys, shared by `@AppStorage` and non-view code.
enum SettingsKey {
    static let autoTranscribe = "autoTranscribe"
    static let recordingFormat = "recording.format"
    static let recordingQuality = "recording.quality"
    static let playbackRate = "playback.rate"
    /// Bundle ID of the app recorded in meetings by default ("" = all system audio).
    static let meetingSource = "meeting.source"
    static let appearance = "appearance"
    /// UID of the microphone ("" = system default).
    static let microphone = "recording.microphone"
    /// Raise quiet microphone recordings to a normal speech level (on by default).
    static let levelsMicrophone = "recording.levelMicrophone"
    static let showsMenuBarIcon = "menuBar.visible"
    /// Tell speakers apart by their voices when transcribing (on by default).
    static let separatesSpeakers = "transcription.separateSpeakers"
    /// Remember voices and recognize people in later recordings (opt-in: voice
    /// profiles are biometric data).
    static let recognizesVoices = "voices.recognize"
    /// Meetings: also split the microphone track (several people in the room; off by default).
    static let separatesRoomSpeakers = "transcription.separateRoomSpeakers"
    /// Look for a new release on GitHub once a day (on by default).
    static let checksForUpdates = "updates.automatic"
    static let lastUpdateCheck = "updates.lastCheck"
    /// Latest release seen on GitHub, so the update note survives a relaunch.
    static let latestReleaseVersion = "updates.latestVersion"
    static let latestReleasePage = "updates.latestPage"
    /// Release the user chose to skip, e.g. "0.2.0".
    static let skippedUpdateVersion = "updates.skippedVersion"
}

/// Light or dark appearance, independent of the system setting if wanted.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .system: "Wie System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    static var current: AppAppearance {
        UserDefaults.standard.string(forKey: SettingsKey.appearance).flatMap(AppAppearance.init) ?? .system
    }

    /// Applies to every window, the dictation HUD and the settings.
    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum RecordingSettings {
    static var fileFormat: RecordingFileFormat {
        UserDefaults.standard.string(forKey: SettingsKey.recordingFormat).flatMap(RecordingFileFormat.init) ?? .aac
    }

    static var quality: RecordingQuality {
        UserDefaults.standard.string(forKey: SettingsKey.recordingQuality).flatMap(RecordingQuality.init) ?? .standard
    }

    static var microphoneUID: String? {
        let value = UserDefaults.standard.string(forKey: SettingsKey.microphone) ?? ""
        return value.isEmpty ? nil : value
    }

    static var levelsMicrophone: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.levelsMicrophone) as? Bool ?? true
    }

    static var meetingSourceBundleID: String? {
        let value = UserDefaults.standard.string(forKey: SettingsKey.meetingSource) ?? ""
        return value.isEmpty ? nil : value
    }
}

enum TranscriptionSettings {
    static var separatesSpeakers: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.separatesSpeakers) as? Bool ?? true
    }

    static var separatesRoomSpeakers: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.separatesRoomSpeakers)
    }

    static var recognizesVoices: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.recognizesVoices)
    }
}

enum PlaybackSettings {
    static var rate: Float {
        get {
            let stored = UserDefaults.standard.float(forKey: SettingsKey.playbackRate)
            return PlayerModel.rates.contains(stored) ? stored : 1
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.playbackRate) }
    }
}
