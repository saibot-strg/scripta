import Foundation

// Enums are persisted as raw strings: SwiftData predicates and sort descriptors
// work reliably on plain String attributes, not on custom enum types.

/// Where a recording came from.
enum RecordingSource: String, Codable, CaseIterable, Sendable {
    case microphone
    case meeting
    case importedFile

    var label: LocalizedStringResource {
        switch self {
        case .microphone: "Mikrofon"
        case .meeting: "Meeting"
        case .importedFile: "Import"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic.fill"
        case .meeting: "person.2.wave.2.fill"
        case .importedFile: "square.and.arrow.down.fill"
        }
    }
}

/// Lifecycle of a recording's transcript. Recording and transcription are
/// separate steps, so every recording starts as `.notTranscribed`.
enum TranscriptionStatus: String, Codable, CaseIterable, Sendable {
    case notTranscribed
    case queued
    case running
    case done
    case failed

    var label: LocalizedStringResource {
        switch self {
        case .notTranscribed: "Nicht transkribiert"
        case .queued: "In Warteschlange"
        case .running: "Läuft"
        case .done: "Fertig"
        case .failed: "Fehler"
        }
    }

    var systemImage: String {
        switch self {
        case .notTranscribed: "text.badge.plus"
        case .queued: "clock"
        case .running: "waveform"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// Queued or running.
    var isInProgress: Bool { self == .queued || self == .running }
}

/// Role of an audio file belonging to a recording.
enum TrackRole: String, Codable, CaseIterable, Sendable {
    /// The file used for playback (mic recording, imported original or meeting mix).
    case primary
    /// Meeting mode: the local microphone ("Ich").
    case microphone
    /// Meeting mode: system / app audio ("Andere").
    case system
}

/// Who is speaking in a transcript segment.
enum SpeakerRole: String, Codable, CaseIterable, Sendable {
    /// Local user, derived from the microphone track.
    case me
    /// Remote participants, derived from the system audio track.
    case others
    /// A speaker found by diarization (numbered).
    case diarized
}
