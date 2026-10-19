import SwiftUI

/// Plain transcript row: timestamp, optional speaker and text.
struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    var showsSpeaker = true
    var isActive = false
    var onSelect: () -> Void = {}
    var onRenameSpeaker: (SpeakerLabel) -> Void = { _ in }
    @State private var isEditing = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button(action: onSelect) {
                Text(Formatters.timestamp(segment.start))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 52, alignment: .trailing)
            .help("Zu dieser Stelle springen")
            .accessibilityLabel(Text("Springe zu \(Formatters.spokenDuration(segment.start))"))

            VStack(alignment: .leading, spacing: 4) {
                if showsSpeaker, let speaker = segment.speaker {
                    Text(speaker.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(speaker.tint)
                }
                EditableSegmentText(segment: segment, isEditing: $isEditing)
                    .font(.body)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if segment.isEdited || isHovered {
                Button("Text bearbeiten", systemImage: "pencil") { isEditing = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(segment.isEdited && !isHovered ? .tertiary : .secondary)
                    .help(segment.isEdited ? "Bearbeitet – klicken zum erneuten Bearbeiten" : "Text bearbeiten")
                    .opacity(isEditing ? 0 : 1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isActive ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .contextMenu {
            SegmentContextMenu(
                segment: segment, onEdit: { isEditing = true }, onPlay: onSelect, onRenameSpeaker: onRenameSpeaker
            )
        }
        .animation(.smooth(duration: 0.25), value: isActive)
    }
}

extension SpeakerLabel {
    /// Accent for "Ich", neutral for everyone else, distinct hues for diarized speakers.
    var tint: Color {
        switch role {
        case .me: .accentColor
        case .others: .secondary
        case .diarized: [.orange, .purple, .teal, .pink, .indigo, .brown][(number - 1).clamped(to: 0...5)]
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
