import Foundation

/// Transcription preferences (UserDefaults), for code outside views.
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
