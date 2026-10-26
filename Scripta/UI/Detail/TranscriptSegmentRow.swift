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
        let showsSpeakerButton = isHovered && !isEditing
        let showsEditButton = !isEditing && (isHovered || segment.isEdited)

        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button(action: onSelect) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Formatters.timestamp(segment.start))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    if let spokenAt = segment.spokenAt {
                        Text(Formatters.clockTime(spokenAt))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(minWidth: 52, alignment: .trailing)
            .help("Zu dieser Stelle springen")
            .accessibilityLabel(Text("Springe zu \(Formatters.spokenDuration(segment.start))"))

            VStack(alignment: .leading, spacing: 4) {
                if showsSpeaker, let speaker = segment.speaker {
                    SpeakerNameMenu(segment: segment, speaker: speaker, style: AnyShapeStyle(speaker.tint), onAssignAll: onRenameSpeaker)
                        .font(.subheadline.weight(.semibold))
                }
                EditableSegmentText(segment: segment, isEditing: $isEditing)
                    .font(.body)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The buttons keep their space while hidden, so the text doesn't
            // re-wrap when the pointer moves over the row.
            if segment.speaker != nil {
                SegmentSpeakerButton(segment: segment, onAssignAll: onRenameSpeaker)
                    .opacity(showsSpeakerButton ? 1 : 0)
                    .disabled(!showsSpeakerButton)
            }
            Button("Text bearbeiten", systemImage: "pencil", action: startEditing)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(segment.isEdited && !isHovered ? .tertiary : .secondary)
                .help(segment.isEdited ? "Bearbeitet – klicken zum erneuten Bearbeiten" : "Text bearbeiten")
                .opacity(showsEditButton ? 1 : 0)
                .disabled(!showsEditButton)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isActive ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .contextMenu {
            SegmentContextMenu(segment: segment, onEdit: startEditing, onPlay: onSelect, onRenameSpeaker: onRenameSpeaker)
        }
        // The hover buttons are out of reach for VoiceOver and Voice Control.
        .accessibilityAction(named: Text("Text bearbeiten"), startEditing)
        .accessibilityAction(named: Text("Ab hier abspielen"), onSelect)
        .animation(.smooth(duration: 0.25), value: isActive)
    }

    private func startEditing() {
        isEditing = true
    }
}
