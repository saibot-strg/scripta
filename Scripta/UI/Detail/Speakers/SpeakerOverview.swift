import Foundation

/// What the assignment sheet shows about one speaker, computed once when the
/// sheet opens rather than on every keystroke in a name field.
struct SpeakerOverview {
    /// The speaker's longest passage, as a sample of what they said.
    let quote: String?
    /// Share of the transcript's speaking time (0...1).
    let share: Double
    /// Up to three of the longest passages, at most 8 s each, to listen to.
    let excerpts: [ExcerptPlayer.Excerpt]

    /// Speakers in order of first appearance, "Ich" last, with their overviews.
    static func make(for transcript: Transcript) -> (speakers: [SpeakerLabel], overviews: [UUID: SpeakerOverview]) {
        var seen: Set<UUID> = []
        let ordered = transcript.orderedSegments.compactMap(\.speaker).filter { seen.insert($0.id).inserted }
        let speakers = ordered.filter { !$0.isLocalUser } + ordered.filter(\.isLocalUser)

        let total = transcript.segments.reduce(0) { $0 + $1.end - $1.start }
        var overviews: [UUID: SpeakerOverview] = [:]
        for speaker in speakers {
            let longest = speaker.segments.sorted { $0.end - $0.start > $1.end - $1.start }
            let spoken = speaker.segments.reduce(0) { $0 + $1.end - $1.start }
            overviews[speaker.id] = SpeakerOverview(
                quote: longest.first?.text,
                share: total > 0 ? spoken / total : 0,
                excerpts: longest.prefix(3).map { ExcerptPlayer.Excerpt(start: $0.start, end: min($0.end, $0.start + 8)) }
            )
        }
        return (speakers, overviews)
    }
}
