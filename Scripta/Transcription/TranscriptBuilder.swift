import Foundation
import NaturalLanguage

/// A speaker within one transcript, before it becomes a `SpeakerLabel`.
struct SpeakerKey: Hashable, Sendable {
    var role: SpeakerRole
    /// 1-based for diarized speakers, 0 otherwise.
    var number = 0

    static let me = SpeakerKey(role: .me)
    static let others = SpeakerKey(role: .others)

    static func diarized(_ number: Int) -> SpeakerKey {
        SpeakerKey(role: .diarized, number: number)
    }
}

/// Segments plus the voice fingerprint of each numbered speaker.
struct DraftTranscript: Sendable {
    var segments: [SegmentDraft]
    var voices: [SpeakerKey: [Float]] = [:]
}

/// A segment before it becomes a SwiftData model.
struct SegmentDraft: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var words: [WordTiming]
    var speaker: SpeakerKey?

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
        speaker: SpeakerKey? = nil,
        pause: TimeInterval = 1.2,
        maxDuration: TimeInterval = 30
    ) -> [SegmentDraft] {
        segments(from: words, speakers: Array(repeating: speaker, count: words.count), pause: pause, maxDuration: maxDuration)
    }

    /// Like `segments(from:speaker:)` with one speaker per word; a change of
    /// speaker also ends the segment.
    static func segments(
        from words: [WordTiming],
        speakers: [SpeakerKey?],
        pause: TimeInterval = 1.2,
        maxDuration: TimeInterval = 30
    ) -> [SegmentDraft] {
        var segments: [SegmentDraft] = []
        var current: [WordTiming] = []
        var currentSpeaker: SpeakerKey?

        func close() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(SegmentDraft(start: first.start, end: last.end, words: current, speaker: currentSpeaker))
            current = []
        }

        for (word, speaker) in zip(words, speakers) {
            if let previous = current.last, let first = current.first {
                let isPause = word.start - previous.end >= pause
                let isTooLong = word.end - first.start > maxDuration
                if isPause || isTooLong || speaker != currentSpeaker { close() }
            }
            current.append(word)
            currentSpeaker = speaker
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

// MARK: - Speakers from diarization

extension TranscriptBuilder {
    /// A further voice on the meeting microphone with less speech than this is
    /// most likely the local user split off or speaker echo, not a person in
    /// the room; it stays "Ich".
    static let minimumVoiceSpeech: TimeInterval = 8

    /// The diarized speaker of each word: the turn overlapping it most, or
    /// else the nearest turn. Nil only without turns.
    static func speakers(of words: [WordTiming], in turns: [SpeakerTurn]) -> [Int?] {
        words.map { word in
            var best: (speaker: Int, overlap: TimeInterval)?
            for turn in turns {
                // Negative overlap is the gap to the turn: nearer is better.
                let overlap = min(word.end, turn.end) - max(word.start, turn.start)
                if let best, best.overlap >= overlap { continue }
                best = (turn.speaker, overlap)
            }
            return best?.speaker
        }
    }

    /// A single track (microphone recording or import): numbered speakers if
    /// diarization found more than one voice, otherwise no speakers.
    static func segments(from words: [WordTiming], diarization: Diarization?) -> [SegmentDraft] {
        transcript(from: words, diarization: diarization).segments
    }

    static func transcript(from words: [WordTiming], diarization: Diarization?) -> DraftTranscript {
        guard let diarization, diarization.speakers.count > 1 else { return DraftTranscript(segments: segments(from: words)) }
        let keys = speakers(of: words, in: diarization.turns).map { $0.map(SpeakerKey.diarized) }
        guard Set(keys).count > 1 else { return DraftTranscript(segments: segments(from: words)) }
        return numbered(segments(from: words, speakers: keys), voices: voices(of: diarization))
    }

    /// Meeting: every voice on the system track becomes a numbered speaker.
    /// On the microphone the main voice stays "Ich"; further voices with
    /// enough speech (people in the same room) become speakers as well.
    static func meetingSegments(
        microphone: [WordTiming],
        microphoneSpeakers: Diarization?,
        system: [WordTiming],
        systemSpeakers: Diarization?
    ) -> [SegmentDraft] {
        meetingTranscript(microphone: microphone, microphoneSpeakers: microphoneSpeakers, system: system, systemSpeakers: systemSpeakers).segments
    }

    static func meetingTranscript(
        microphone: [WordTiming],
        microphoneSpeakers: Diarization?,
        system: [WordTiming],
        systemSpeakers: Diarization?
    ) -> DraftTranscript {
        var others = segments(from: system, speaker: .others)
        var systemCount = 0
        var allVoices: [SpeakerKey: [Float]] = [:]
        if let systemSpeakers, !systemSpeakers.turns.isEmpty {
            let keys = speakers(of: system, in: systemSpeakers.turns).map { $0.map(SpeakerKey.diarized) }
            others = segments(from: system, speakers: keys)
            systemCount = systemSpeakers.speakers.max() ?? 0
            allVoices = voices(of: systemSpeakers)
        }

        guard let microphoneSpeakers, microphoneSpeakers.speakers.count > 1 else {
            return numbered(mergeMeeting(me: segments(from: microphone, speaker: .me), others: others), voices: allVoices)
        }
        // Numbered after the system voices; the main voice is chosen after
        // echo removal, so echo of the speakers cannot become "Ich".
        let keys = speakers(of: microphone, in: microphoneSpeakers.turns).map { speaker in
            speaker.map { SpeakerKey.diarized(systemCount + $0) }
        }
        allVoices.merge(voices(of: microphoneSpeakers, offset: systemCount)) { first, _ in first }
        let me = segments(from: microphone, speakers: keys)
        var merged = mergeMeeting(me: me, others: others)
        let voices = Set(keys.compactMap { $0 })
        if let main = mainVoice(among: voices, in: merged) {
            let mine = weakVoices(voices.subtracting([main]), in: merged).union([main])
            merged = relabeling(mine, as: .me, in: merged)
        }
        return numbered(merged, voices: allVoices)
    }

    private static func voices(of diarization: Diarization, offset: Int = 0) -> [SpeakerKey: [Float]] {
        Dictionary(uniqueKeysWithValues: diarization.embeddings.map { (SpeakerKey.diarized(offset + $0.key), $0.value) })
    }

    /// The voice with the most speech among `voices`.
    private static func mainVoice(among voices: Set<SpeakerKey>, in segments: [SegmentDraft]) -> SpeakerKey? {
        voices.max { speech(of: $0, in: segments) < speech(of: $1, in: segments) }
    }

    /// Those of `voices` with too little speech to be a person of their own.
    private static func weakVoices(_ voices: Set<SpeakerKey>, in segments: [SegmentDraft]) -> Set<SpeakerKey> {
        voices.filter { speech(of: $0, in: segments) < minimumVoiceSpeech }
    }

    private static func relabeling(_ voices: Set<SpeakerKey>, as target: SpeakerKey, in segments: [SegmentDraft]) -> [SegmentDraft] {
        segments.map { segment in
            guard let speaker = segment.speaker, voices.contains(speaker) else { return segment }
            var copy = segment
            copy.speaker = target
            return copy
        }
    }

    private static func speech(of speaker: SpeakerKey, in segments: [SegmentDraft]) -> TimeInterval {
        segments.filter { $0.speaker == speaker }.reduce(0) { $0 + $1.end - $1.start }
    }

    /// Numbers diarized speakers 1, 2, 3 … in order of first appearance.
    static func renumbered(_ segments: [SegmentDraft]) -> [SegmentDraft] {
        numbered(segments, voices: [:]).segments
    }

    /// Like `renumbered`, carrying each speaker's voice along. Voices of
    /// speakers no longer in the segments (merged into "Ich") are dropped.
    static func numbered(_ segments: [SegmentDraft], voices: [SpeakerKey: [Float]]) -> DraftTranscript {
        var numbers: [Int: Int] = [:]
        let segments = segments.map { segment in
            guard let speaker = segment.speaker, speaker.role == .diarized else { return segment }
            let number = numbers[speaker.number] ?? numbers.count + 1
            numbers[speaker.number] = number
            var copy = segment
            copy.speaker = .diarized(number)
            return copy
        }
        var renumberedVoices: [SpeakerKey: [Float]] = [:]
        for (old, new) in numbers {
            renumberedVoices[.diarized(new)] = voices[.diarized(old)]
        }
        return DraftTranscript(segments: segments, voices: renumberedVoices)
    }
}
