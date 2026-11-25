import SwiftUI

/// One voice's turns on the playback timeline.
struct SpeakerLane: Identifiable {
    let id: UUID
    /// Nil for transcripts without speakers.
    let speaker: SpeakerLabel?
    var spans: [ClosedRange<TimeInterval>]

    /// The speaker's color; a meeting's "Andere" gets the brand blue of the live levels.
    var tint: Color {
        guard let speaker else { return .accentColor }
        return speaker.role == .others ? .brandSky : speaker.tint
    }
}

/// Builds the lanes of the playback timeline from a transcript's passages.
enum SpeakerLanes {
    /// Passages of one voice closer together than this are drawn as one turn.
    static let mergeGap: TimeInterval = 1.5

    /// Merges passages (in time order) into turns per key; keys keep the order
    /// in which they first appear.
    static func turns<Key: Hashable>(
        _ passages: [(key: Key, start: TimeInterval, end: TimeInterval)],
        mergingGapsUnder gap: TimeInterval = mergeGap
    ) -> [(key: Key, spans: [ClosedRange<TimeInterval>])] {
        var order: [Key] = []
        var spansByKey: [Key: [ClosedRange<TimeInterval>]] = [:]
        for passage in passages {
            let end = max(passage.end, passage.start)
            guard var spans = spansByKey[passage.key] else {
                order.append(passage.key)
                spansByKey[passage.key] = [passage.start...end]
                continue
            }
            if let last = spans.last, passage.start - last.upperBound < gap, passage.start >= last.lowerBound {
                spans[spans.count - 1] = last.lowerBound...max(last.upperBound, end)
            } else {
                spans.append(passage.start...end)
            }
            spansByKey[passage.key] = spans
        }
        return order.map { (key: $0, spans: spansByKey[$0] ?? []) }
    }

    /// The user's own lane first, the other voices as they first speak.
    static func make(from segments: [TranscriptSegment]) -> [SpeakerLane] {
        let unassigned = UUID()
        var speakers: [UUID: SpeakerLabel] = [:]
        let passages = segments.map { segment -> (key: UUID, start: TimeInterval, end: TimeInterval) in
            if let speaker = segment.speaker { speakers[speaker.id] = speaker }
            return (key: segment.speaker?.id ?? unassigned, start: segment.start, end: segment.end)
        }
        let lanes = turns(passages).map { SpeakerLane(id: $0.key, speaker: speakers[$0.key], spans: $0.spans) }
        return lanes.filter { $0.speaker?.isLocalUser == true } + lanes.filter { $0.speaker?.isLocalUser != true }
    }
}
