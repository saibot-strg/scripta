import AVFAudio
import Foundation

/// Microphone permission (TCC). Requires `NSMicrophoneUsageDescription` and the
/// `com.apple.security.device.audio-input` entitlement.
enum MicrophonePermission {
    /// Asks for access on first use; throws if the user declined earlier.
    static func ensureAccess() async throws(RecordingError) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                throw .microphoneAccessDenied
            }
        case .denied:
            throw .microphoneAccessDenied
        @unknown default:
            throw .microphoneAccessDenied
        }
    }
}

/// Deep links into System Settings › Privacy & Security.
enum PrivacyPane {
    case microphone
    case systemAudio
    /// Also the place for "send keystrokes" (dictation pastes with ⌘V).
    case accessibility

    var url: URL? {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .systemAudio:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}

/// Errors that can point the user to a privacy pane in System Settings.
protocol PrivacySettingsLinking {
    var privacySettingsURL: URL? { get }
}
