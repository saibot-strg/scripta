import Foundation
import SwiftData

extension LibrarySchemaV2 {
    /// A recording or imported file in the library.
    ///
    /// Audio data never lives in the database. Each recording owns a folder named
    /// after its `id` inside a storage root; tracks reference files in that folder.
    @Model
    final class Recording {
        /// Stable identifier; also the name of the recording's folder on disk.
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        /// Duration in seconds.
        var duration: TimeInterval
        var sourceRaw: String
        var statusRaw: String
        /// 0...1 while a transcription is running.
        var transcriptionProgress: Double
        /// User-facing error message of the last failed transcription.
        var errorMessage: String?
        /// Language requested for transcription (BCP-47, nil = automatic).
        var languageCode: String?
        /// Security-scoped bookmark of the storage root folder, if the recording
        /// lives outside the app container (nil = default container location).
        var storageRootBookmark: Data?

        @Relationship(deleteRule: .cascade, inverse: \AudioTrack.recording)
        var tracks: [AudioTrack] = []

        @Relationship(deleteRule: .cascade, inverse: \Transcript.recording)
        var transcript: Transcript?

        /// The sidebar folder it was filed in (since schema 2).
        var folder: Folder?

        init(
            id: UUID = UUID(),
            title: String,
            createdAt: Date = .now,
            duration: TimeInterval = 0,
            source: RecordingSource,
            status: TranscriptionStatus = .notTranscribed,
            languageCode: String? = nil
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.duration = duration
            self.sourceRaw = source.rawValue
            self.statusRaw = status.rawValue
            self.transcriptionProgress = 0
            self.languageCode = languageCode
        }
    }
}

extension Recording {
    var source: RecordingSource {
        get { RecordingSource(rawValue: sourceRaw) ?? .importedFile }
        set { sourceRaw = newValue.rawValue }
    }

    var status: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: statusRaw) ?? .notTranscribed }
        set { statusRaw = newValue.rawValue }
    }

    /// The track used for playback.
    var primaryTrack: AudioTrack? {
        tracks.first { $0.role == .primary }
    }

    /// Case- and diacritic-insensitive match against title and transcript text.
    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if title.localizedStandardContains(query) { return true }
        return transcript?.fullText.localizedStandardContains(query) ?? false
    }
}
