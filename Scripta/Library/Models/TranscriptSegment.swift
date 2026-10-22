import Foundation
import SwiftData

/// Timing of a single word inside a segment.
struct WordTiming: Codable, Hashable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var confidence: Float?
}

extension LibrarySchemaV2 {
    /// A timed section of a transcript (roughly a sentence or a speaker turn).
    @Model
    final class TranscriptSegment {
        var id: UUID
        /// Position within the transcript; tie-breaker for equal start times.
        var index: Int
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        /// Engine output before the first manual edit (nil = never edited).
        var originalText: String?
        /// Word timings, JSON-encoded. Stored as one blob per segment instead of
        /// thousands of rows, which keeps 60-minute transcripts fast to load and save.
        var wordsData: Data?

        var speaker: SpeakerLabel?

        var transcript: Transcript?

        init(index: Int, start: TimeInterval, end: TimeInterval, text: String, words: [WordTiming] = []) {
            self.id = UUID()
            self.index = index
            self.start = start
            self.end = end
            self.text = text
            self.wordsData = words.isEmpty ? nil : try? JSONEncoder().encode(words)
        }
    }
}

extension TranscriptSegment {
    var isEdited: Bool { originalText != nil }

    /// When this was said, for recordings made in Scripta (they start at
    /// `createdAt`). Nil for imports: their creation date is the import.
    var spokenAt: Date? {
        guard let recording = transcript?.recording, recording.source != .importedFile else { return nil }
        return recording.createdAt.addingTimeInterval(start)
    }

    var words: [WordTiming] {
        guard let wordsData else { return [] }
        return (try? JSONDecoder().decode([WordTiming].self, from: wordsData)) ?? []
    }

    /// Applies a manual correction and keeps the engine's original text once.
    func applyEdit(_ newText: String) {
        guard newText != text else { return }
        if originalText == nil { originalText = text }
        text = newText
    }
}
