import Foundation
import SwiftData

extension LibrarySchemaV2 {
    /// The transcript of a recording: ordered segments plus the speakers in it.
    @Model
    final class Transcript {
        var id: UUID
        var createdAt: Date
        var modifiedAt: Date
        /// Detected or requested language (BCP-47).
        var languageCode: String?
        /// Identifier of the engine/model that produced the transcript.
        var engineIdentifier: String
        /// Denormalized plain text of all segments, used for library search.
        var fullText: String

        @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.transcript)
        var segments: [TranscriptSegment] = []

        @Relationship(deleteRule: .cascade, inverse: \SpeakerLabel.transcript)
        var speakers: [SpeakerLabel] = []

        var recording: Recording?

        init(id: UUID = UUID(), languageCode: String? = nil, engineIdentifier: String, createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.modifiedAt = createdAt
            self.languageCode = languageCode
            self.engineIdentifier = engineIdentifier
            self.fullText = ""
        }
    }
}

extension Transcript {
    /// Segments in playback order (SwiftData does not preserve array order).
    var orderedSegments: [TranscriptSegment] {
        segments.sorted { ($0.start, $0.index) < ($1.start, $1.index) }
    }

    /// True if the transcript has more than one speaker label in use.
    var hasSpeakers: Bool {
        Set(segments.compactMap { $0.speaker?.id }).count > 1
    }

    /// Rebuilds `fullText` after segments were added or edited.
    func rebuildFullText() {
        fullText = orderedSegments.map(\.text).joined(separator: "\n")
        modifiedAt = .now
    }
}
