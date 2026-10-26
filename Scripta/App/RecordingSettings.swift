import Foundation

/// Recording preferences (UserDefaults), for code outside views.
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
