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
    /// The user confirmed the notice to tell others about meeting recordings.
    static let meetingNoticeConfirmed = "meeting.noticeConfirmed"
    /// The app's own language ("AppleLanguages" in the app's defaults).
    static let appleLanguages = "AppleLanguages"
}
