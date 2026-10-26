import SwiftUI

/// Small person button shown while hovering a passage; opens the same
/// choices as the speaker's name.
struct SegmentSpeakerButton: View {
    let segment: TranscriptSegment
    let onAssignAll: (SpeakerLabel) -> Void

    var body: some View {
        Menu("Sprecher dieser Sprechblase", systemImage: "person.crop.circle") {
            SegmentSpeakerMenuItems(segment: segment, onAssignAll: onAssignAll)
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Wem gehört diese Sprechblase?")
    }
}
