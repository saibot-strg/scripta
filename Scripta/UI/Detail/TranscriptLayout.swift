import Foundation

/// A transcript's segments in playback order, grouped by speaker, plus the
/// timeline for playback. Built once per transcript version, so playback
/// (a new active segment every few seconds) doesn't sort the transcript again.
struct TranscriptLayout {
    struct Row: Identifiable {
        let id: UUID
        let segment: TranscriptSegment
        /// First passage of a speaker turn: shows the name, more space above.
        let isNewSpeaker: Bool
        let isFirst: Bool

        func topSpacing(for style: TranscriptStyle) -> CGFloat {
            guard !isFirst else { return 0 }
            return switch style {
            case .text: isNewSpeaker ? 14 : 4
            case .bubbles: isNewSpeaker ? 14 : 3
            }
        }
    }

    private(set) var transcriptID: UUID?
    private(set) var version: Date?
    private(set) var rows: [Row] = []
    private(set) var timeline = TranscriptTimeline.empty

    static var empty: TranscriptLayout { TranscriptLayout() }

    private init() {}

    init(_ transcript: Transcript) {
        let segments = transcript.orderedSegments
        transcriptID = transcript.id
        version = transcript.modifiedAt
        timeline = TranscriptTimeline(segments)
        var previousSpeaker: UUID?
        rows = segments.enumerated().map { offset, segment in
            let speaker = segment.speaker?.id
            defer { previousSpeaker = speaker }
            return Row(id: segment.id, segment: segment, isNewSpeaker: offset == 0 || speaker != previousSpeaker, isFirst: offset == 0)
        }
    }

    /// False once the transcript was edited or replaced.
    func isCurrent(for transcript: Transcript) -> Bool {
        transcriptID == transcript.id && version == transcript.modifiedAt
    }
}
