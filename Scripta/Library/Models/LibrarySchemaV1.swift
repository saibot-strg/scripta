import Foundation
import SwiftData

/// Version 1 of the library schema, frozen: SwiftData needs the exact old
/// models to migrate stores created by Scripta 0.1–0.3.1. Never change these;
/// add a new schema version instead.
enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Recording.self, AudioTrack.self, Transcript.self, TranscriptSegment.self, SpeakerLabel.self]
    }

    @Model
    final class Recording {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var duration: TimeInterval
        var sourceRaw: String
        var statusRaw: String
        var transcriptionProgress: Double
        var errorMessage: String?
        var languageCode: String?
        var storageRootBookmark: Data?

        @Relationship(deleteRule: .cascade, inverse: \AudioTrack.recording)
        var tracks: [AudioTrack] = []

        @Relationship(deleteRule: .cascade, inverse: \Transcript.recording)
        var transcript: Transcript?

        init(id: UUID = UUID(), title: String, createdAt: Date = .now, duration: TimeInterval = 0, sourceRaw: String, statusRaw: String) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.duration = duration
            self.sourceRaw = sourceRaw
            self.statusRaw = statusRaw
            self.transcriptionProgress = 0
        }
    }

    @Model
    final class AudioTrack {
        var id: UUID
        var roleRaw: String
        var fileName: String
        var duration: TimeInterval
        var recording: Recording?

        init(roleRaw: String, fileName: String) {
            self.id = UUID()
            self.roleRaw = roleRaw
            self.fileName = fileName
            self.duration = 0
        }
    }

    @Model
    final class Transcript {
        var id: UUID
        var createdAt: Date
        var modifiedAt: Date
        var languageCode: String?
        var engineIdentifier: String
        var fullText: String

        @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.transcript)
        var segments: [TranscriptSegment] = []

        @Relationship(deleteRule: .cascade, inverse: \SpeakerLabel.transcript)
        var speakers: [SpeakerLabel] = []

        var recording: Recording?

        init(engineIdentifier: String) {
            self.id = UUID()
            self.createdAt = .now
            self.modifiedAt = .now
            self.engineIdentifier = engineIdentifier
            self.fullText = ""
        }
    }

    @Model
    final class TranscriptSegment {
        var id: UUID
        var index: Int
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        var originalText: String?
        var wordsData: Data?

        var speaker: SpeakerLabel?

        var transcript: Transcript?

        init(index: Int, start: TimeInterval, end: TimeInterval, text: String) {
            self.id = UUID()
            self.index = index
            self.start = start
            self.end = end
            self.text = text
        }
    }

    @Model
    final class SpeakerLabel {
        var id: UUID
        var roleRaw: String
        var number: Int
        var customName: String?
        var transcript: Transcript?

        @Relationship(deleteRule: .nullify, inverse: \TranscriptSegment.speaker)
        var segments: [TranscriptSegment] = []

        init(roleRaw: String, number: Int) {
            self.id = UUID()
            self.roleRaw = roleRaw
            self.number = number
        }
    }
}
