import Foundation
import SwiftData

/// The speakers of one transcript at one moment: who exists, what they are
/// called, which passage belongs to whom and what Scripta knows about their
/// voices. Restoring it undoes renaming, merging and moving passages.
@MainActor
struct SpeakerSnapshot {
    struct Label {
        let id: UUID
        let role: SpeakerRole
        let number: Int
        let customName: String?
        let voice: VoiceStatus?
    }

    let transcriptID: UUID
    private let labels: [Label]
    /// Segment ID → speaker ID (nil: no speaker).
    private let assignments: [UUID: UUID?]

    init(_ transcript: Transcript, voices: VoiceLibrary) {
        transcriptID = transcript.id
        labels = transcript.speakers.map { speaker in
            Label(id: speaker.id, role: speaker.role, number: speaker.number, customName: speaker.customName, voice: voices.statuses[speaker.id])
        }
        assignments = Dictionary(uniqueKeysWithValues: transcript.segments.map { ($0.id, $0.speaker?.id) })
    }

    /// Brings `transcript` back to this state. Speakers removed since (merged)
    /// are recreated with their old ID; speakers added since are removed. A
    /// voice that was dropped meanwhile (moved passages) stays dropped.
    func restore(into transcript: Transcript, context: ModelContext, voices: VoiceLibrary) {
        var speakers = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0) })
        for label in labels where speakers[label.id] == nil {
            let speaker = SpeakerLabel(role: label.role, number: label.number, customName: label.customName)
            speaker.id = label.id
            transcript.speakers.append(speaker)
            speakers[label.id] = speaker
        }
        for segment in transcript.segments {
            guard let assigned = assignments[segment.id] else { continue }
            let speaker = assigned.flatMap { speakers[$0] }
            if segment.speaker?.id != speaker?.id { segment.speaker = speaker }
        }
        let kept = Set(labels.map(\.id))
        for speaker in transcript.speakers where !kept.contains(speaker.id) {
            transcript.speakers.removeAll { $0.id == speaker.id }
            context.delete(speaker)
        }
        for label in labels {
            speakers[label.id]?.customName = label.customName
            if voices.statuses[label.id] != label.voice {
                voices.restore(labelID: label.id, to: label.voice)
            }
        }
    }
}
