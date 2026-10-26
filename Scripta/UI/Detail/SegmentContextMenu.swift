import AppKit
import SwiftUI

/// Context menu of a transcript segment.
struct SegmentContextMenu: View {
    @Environment(AppModel.self) private var appModel
    let segment: TranscriptSegment
    let onEdit: () -> Void
    let onPlay: () -> Void
    let onRenameSpeaker: (SpeakerLabel) -> Void

    var body: some View {
        Button("Ab hier abspielen", systemImage: "play", action: onPlay)
        Button("Text bearbeiten", systemImage: "pencil", action: onEdit)
        if segment.isEdited {
            Button("Originaltext wiederherstellen", systemImage: "arrow.uturn.backward") {
                appModel.restoreOriginalText(of: segment)
            }
        }
        Button("Abschnitt kopieren", systemImage: "doc.on.doc", action: copy)
        if let speaker = segment.speaker {
            Divider()
            Button("„\(speaker.displayName)“ umbenennen …", systemImage: "person.text.rectangle") {
                onRenameSpeaker(speaker)
            }
            let others = (speaker.transcript?.speakers ?? [])
                .filter { $0.id != speaker.id }
                .sorted(by: SpeakerLabel.menuOrder)
            if !others.isEmpty {
                Menu("„\(speaker.displayName)“ zuordnen zu", systemImage: "person.2") {
                    ForEach(others) { other in
                        Button(other.displayName) { appModel.merge(speaker, into: other) }
                    }
                }
            }
            // Two people in one voice: move single passages out.
            Menu("Nur diesen Abschnitt", systemImage: "arrow.turn.down.right") {
                ForEach(others) { other in
                    Button(other.displayName) { appModel.move(segment, to: other) }
                }
                if !others.isEmpty { Divider() }
                Button("Neuer Sprecher", systemImage: "person.badge.plus") { appModel.moveToNewSpeaker(segment) }
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(segment.text, forType: .string)
    }
}
