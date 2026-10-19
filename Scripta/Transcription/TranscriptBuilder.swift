import Foundation
import NaturalLanguage

/// A segment before it becomes a SwiftData model.
struct SegmentDraft: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var words: [WordTiming]
    var speaker: SpeakerRole?

    var text: String { words.map(\.text).joined(separator: " ") }
}

/// Turns timed words into readable segments and merges meeting tracks.
enum TranscriptBuilder {
    /// Sentence-ending punctuation.
    private static let sentenceEnd: Set<Character> = [".", "?", "!", "…"]

    /// Splits words into segments: after a sentence ends, at pauses, and at
    /// the latest after `maxDuration` (long monologues without punctuation).
    static func segments(
        from words: [WordTiming],
        speaker: SpeakerRole? = nil,
        pause: TimeInterval = 1.2,
        maxDuration: TimeInterval = 30
    ) -> [SegmentDraft] {
        var segments: [SegmentDraft] = []
        var current: [WordTiming] = []

        func close() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(SegmentDraft(start: first.start, end: last.end, words: current, speaker: speaker))
            current = []
        }

        for word in words {
            if let previous = current.last, let first = current.first {
                let isPause = word.start - previous.end >= pause
                let isTooLong = word.end - first.start > maxDuration
                if isPause || isTooLong { close() }
            }
            current.append(word)
            if let lastCharacter = word.text.last, sentenceEnd.contains(lastCharacter) {
                close()
            }
        }
        close()
        return segments
    }

    /// Merges "Ich" (microphone) and "Andere" (system audio) by time.
    ///
    /// Without headphones the microphone also picks up the other participants
    /// from the speakers. Such echo segments repeat what the system track
    /// already has at the same time, so they are dropped.
    static func mergeMeeting(me: [SegmentDraft], others: [SegmentDraft]) -> [SegmentDraft] {
        let filteredMe = me.filter { segment in
            !others.contains { other in isEcho(segment, of: other) }
        }
        return (filteredMe + others).sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    static func isEcho(_ segment: SegmentDraft, of other: SegmentDraft) -> Bool {
        let overlap = min(segment.end, other.end) - max(segment.start, other.start)
        let length = max(segment.end - segment.start, 0.1)
        guard overlap / length >= 0.5 else { return false }
        let mine = normalizedWords(segment.text)
        let theirs = normalizedWords(other.text)
        guard !mine.isEmpty else { return false }
        return Double(mine.intersection(theirs).count) / Double(mine.count) >= 0.6
    }

    private static func normalizedWords(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
    }

    /// Dominant language (BCP-47) of the text. Parakeet detects the language
    /// itself but does not report it.
    static func detectLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
