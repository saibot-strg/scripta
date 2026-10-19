import AppKit
import SwiftUI

/// Messages-style bubble: "Ich" on the right in the accent color, others on the left.
struct ChatBubbleRow: View {
    let segment: TranscriptSegment
    var showsHeader = true
    var isActive = false
    var onSelect: () -> Void = {}
    var onRenameSpeaker: (SpeakerLabel) -> Void = { _ in }
    @State private var isEditing = false

    private var isMe: Bool { segment.speaker?.isLocalUser ?? false }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMe { Spacer(minLength: 72) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                if showsHeader || segment.isEdited {
                    header
                }
                EditableSegmentText(segment: segment, isEditing: $isEditing)
                    .font(.body)
                    .lineSpacing(2)
                    .foregroundStyle(isMe ? Color.white : Color.primary)
                    .frame(minWidth: isEditing ? 240 : nil, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(bubbleFill, in: .rect(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if isActive || isEditing {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .padding(-3)
                        }
                    }
                    .contextMenu {
                        SegmentContextMenu(
                            segment: segment, onEdit: { isEditing = true }, onPlay: onSelect, onRenameSpeaker: onRenameSpeaker
                        )
                    }
            }

            if !isMe { Spacer(minLength: 72) }
        }
        .animation(.smooth(duration: 0.25), value: isActive)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let speaker = segment.speaker {
                Text(speaker.displayName)
                    .fontWeight(.semibold)
            }
            Button(action: onSelect) {
                Text(Formatters.timestamp(segment.start))
                    .monospacedDigit()
            }
            .buttonStyle(.plain)
            .help("Zu dieser Stelle springen")
            if segment.isEdited {
                EditedMarker()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private var bubbleFill: AnyShapeStyle {
        isMe ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(nsColor: .secondarySystemFill))
    }
}
