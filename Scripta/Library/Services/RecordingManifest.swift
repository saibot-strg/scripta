import Foundation

/// Metadata written next to an in-progress recording.
///
/// It is removed once the recording is in the library. A manifest found at
/// launch means the app ended unexpectedly while recording; the audio written
/// so far is then added to the library (see `RecordingRecovery`).
struct RecordingManifest: Codable, Sendable, Equatable {
    static let fileName = "recording.json"

    var id: UUID
    var title: String
    var createdAt: Date
    var source: RecordingSource
    /// Playback file inside the recording folder. For meetings it is the mix
    /// of both tracks, created after recording stops.
    var fileName: String
    /// Meeting only: the separate microphone ("Ich") and system ("Andere") tracks.
    var microphoneFileName: String?
    var systemFileName: String?

    var isMeeting: Bool { systemFileName != nil }

    /// Track files written while recording.
    var capturedFileNames: [String] {
        isMeeting ? [microphoneFileName, systemFileName].compactMap { $0 } : [fileName]
    }

    /// The microphone ("Ich") track; a microphone recording has no other.
    var microphoneTrackFileName: String? {
        isMeeting ? microphoneFileName : fileName
    }
}

extension RecordingStorage {
    func manifestURL(for recordingID: UUID) -> URL {
        fileURL(for: recordingID, fileName: RecordingManifest.fileName)
    }

    func writeManifest(_ manifest: RecordingManifest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL(for: manifest.id), options: .atomic)
    }

    func readManifest(in folder: URL) -> RecordingManifest? {
        let url = folder.appending(path: RecordingManifest.fileName, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecordingManifest.self, from: data)
    }

    func removeManifest(for recordingID: UUID) {
        try? FileManager.default.removeItem(at: manifestURL(for: recordingID))
    }

    /// All recording folders below the storage root.
    func recordingFolders() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
