import SwiftUI

/// Renders transcript segments as plain timed text or as chat bubbles.
///
/// Emits rows directly into the parent's lazy stack (no own container), so
/// only visible segments are built.
struct TranscriptView: View {
    let transcript: Transcript
    let style: TranscriptStyle
    /// Segment currently playing (wired to the player in milestone 3).
    var activeSegmentID: UUID?
    var onSelect: (TranscriptSegment) -> Void = { _ in }
    var onRenameSpeaker: (SpeakerLabel) -> Void = { _ in }

    var body: some View {
        let segments = transcript.orderedSegments
        ForEach(Array(segments.enumerated()), id: \.element.id) { offset, segment in
            let previousSpeaker = offset > 0 ? segments[offset - 1].speaker?.id : nil
            let isNewSpeaker = offset == 0 || previousSpeaker != segment.speaker?.id

            Group {
                switch style {
                case .text:
                    TranscriptSegmentRow(
                        segment: segment,
                        showsSpeaker: isNewSpeaker,
                        isActive: segment.id == activeSegmentID,
                        onSelect: { onSelect(segment) },
                        onRenameSpeaker: onRenameSpeaker
                    )
                case .bubbles:
                    ChatBubbleRow(
                        segment: segment,
                        showsHeader: isNewSpeaker,
                        isActive: segment.id == activeSegmentID,
                        onSelect: { onSelect(segment) },
                        onRenameSpeaker: onRenameSpeaker
                    )
                }
            }
            .padding(.top, rowSpacing(isNewSpeaker: isNewSpeaker, isFirst: offset == 0))
        }
    }

    private func rowSpacing(isNewSpeaker: Bool, isFirst: Bool) -> CGFloat {
        guard !isFirst else { return 0 }
        return switch style {
        case .text: isNewSpeaker ? 14 : 4
        case .bubbles: isNewSpeaker ? 14 : 3
        }
    }
}
