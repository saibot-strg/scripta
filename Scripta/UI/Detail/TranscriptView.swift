import SwiftUI

/// Renders transcript rows as plain timed text or as chat bubbles.
///
/// Emits rows directly into the parent's lazy stack (no own container), so
/// only visible segments are built. The style is chosen outside the
/// `ForEach`, so every element yields the same kind of view and the lazy
/// stack can identify rows without evaluating them.
struct TranscriptView: View {
    let rows: [TranscriptLayout.Row]
    let style: TranscriptStyle
    /// Segment currently playing.
    var activeSegmentID: UUID?
    var onSelect: (TranscriptSegment) -> Void = { _ in }
    var onRenameSpeaker: (SpeakerLabel) -> Void = { _ in }

    var body: some View {
        switch style {
        case .text:
            ForEach(rows) { row in
                TranscriptSegmentRow(
                    segment: row.segment,
                    showsSpeaker: row.isNewSpeaker,
                    isActive: row.id == activeSegmentID,
                    onSelect: { onSelect(row.segment) },
                    onRenameSpeaker: onRenameSpeaker
                )
                .padding(.top, row.topSpacing(for: .text))
            }
        case .bubbles:
            ForEach(rows) { row in
                ChatBubbleRow(
                    segment: row.segment,
                    showsHeader: row.isNewSpeaker,
                    isActive: row.id == activeSegmentID,
                    onSelect: { onSelect(row.segment) },
                    onRenameSpeaker: onRenameSpeaker
                )
                .padding(.top, row.topSpacing(for: .bubbles))
            }
        }
    }
}
