import SwiftUI

/// A speaker's name above their text. A click opens the choices for this
/// passage; a guessed name carries a "?", a click on it confirms.
struct SpeakerNameMenu: View {
    @Environment(AppModel.self) private var appModel
    let segment: TranscriptSegment
    let speaker: SpeakerLabel
    let style: AnyShapeStyle
    /// Opens the assignment sheet for all of a speaker's passages.
    let onAssignAll: (SpeakerLabel) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                SegmentSpeakerMenuItems(segment: segment, onAssignAll: onAssignAll)
            } label: {
                Text(speaker.displayName)
                    .foregroundStyle(style)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Wem gehört diese Sprechblase?")

            if speaker.isGuess(in: appModel.voices) {
                Button(action: confirm) {
                    Text(verbatim: "?")
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: .capsule)
                }
                .buttonStyle(.plain)
                .help("Vermutet – klicken zum Bestätigen, auf den Namen klicken zum Ändern")
                .accessibilityLabel(Text("Vermuteten Namen „\(speaker.displayName)“ bestätigen"))
            }
        }
    }

    private func confirm() {
        appModel.confirmSuggestion(for: speaker)
    }
}
