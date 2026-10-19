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
    static let showsMenuBarIcon = "menuBar.visible"
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

    static var meetingSourceBundleID: String? {
        let value = UserDefaults.standard.string(forKey: SettingsKey.meetingSource) ?? ""
        return value.isEmpty ? nil : value
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
