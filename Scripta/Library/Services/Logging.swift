import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Scripta"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let library = Logger(subsystem: subsystem, category: "Library")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let recording = Logger(subsystem: subsystem, category: "Recording")
    static let playback = Logger(subsystem: subsystem, category: "Playback")
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    static let dictation = Logger(subsystem: subsystem, category: "Dictation")
    static let voices = Logger(subsystem: subsystem, category: "Voices")
}
