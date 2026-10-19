import Foundation

/// Errors while recording, with user-facing German descriptions.
enum RecordingError: LocalizedError {
    case microphoneAccessDenied
    case noInputDevice
    case alreadyRecording
    case engineFailed(underlying: any Error)
    case fileFailed(underlying: any Error)
    case writeFailed(message: String)
    case systemAudioFailed(underlying: any Error)
    case notEnoughSpace

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            String(localized: "Kein Zugriff auf das Mikrofon")
        case .noInputDevice:
            String(localized: "Kein Mikrofon gefunden")
        case .alreadyRecording:
            String(localized: "Es läuft bereits eine Aufnahme.")
        case .engineFailed:
            String(localized: "Die Aufnahme konnte nicht gestartet werden.")
        case .fileFailed:
            String(localized: "Die Aufnahmedatei konnte nicht angelegt werden.")
        case .writeFailed:
            String(localized: "Die Aufnahme wurde unterbrochen.")
        case .systemAudioFailed:
            String(localized: "Systemaudio kann nicht aufgenommen werden.")
        case .notEnoughSpace:
            String(localized: "Zu wenig freier Speicherplatz")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphoneAccessDenied:
            String(localized: "Erlaube Scripta den Zugriff in den Systemeinstellungen unter „Datenschutz & Sicherheit“ → „Mikrofon“.")
        case .noInputDevice:
            String(localized: "Schließe ein Mikrofon an oder wähle in den Systemeinstellungen ein Eingabegerät.")
        case .writeFailed:
            String(localized: "Alles bis zu diesem Zeitpunkt wurde gespeichert. Prüfe, ob genug Speicherplatz frei ist.")
        case .systemAudioFailed:
            String(localized: "Erlaube Scripta in den Systemeinstellungen unter „Datenschutz & Sicherheit“ → „Bildschirm- & Systemaudioaufnahme“ die Systemaudio-Aufnahme.")
        case .notEnoughSpace:
            String(localized: "Für eine Aufnahme werden mindestens 500 MB freier Speicher benötigt. Lösche nicht mehr benötigte Dateien oder wähle in den Einstellungen einen anderen Speicherort.")
        case .alreadyRecording, .engineFailed, .fileFailed:
            nil
        }
    }

    var failureReason: String? {
        switch self {
        case .engineFailed(let error), .fileFailed(let error), .systemAudioFailed(let error):
            error.localizedDescription
        case .writeFailed(let message):
            message
        case .microphoneAccessDenied, .noInputDevice, .alreadyRecording, .notEnoughSpace:
            nil
        }
    }
}

extension RecordingError: PrivacySettingsLinking {
    var privacySettingsURL: URL? {
        switch self {
        case .microphoneAccessDenied: PrivacyPane.microphone.url
        case .systemAudioFailed: PrivacyPane.systemAudio.url
        default: nil
        }
    }
}
