import AppKit
import SwiftUI

/// A segment's text that turns into an editor on demand. Return saves,
/// Escape cancels, clicking elsewhere saves.
struct EditableSegmentText: View {
    @Environment(AppModel.self) private var appModel
    let segment: TranscriptSegment
    @Binding var isEditing: Bool
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField("Text", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onAppear {
                    draft = segment.text
                    isFocused = true
                }
                .onSubmit(commit)
                .onExitCommand { isEditing = false }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .accessibilityLabel(Text("Abschnitt bearbeiten"))
        } else {
            // Not selectable: selectable text answers a right-click with the
            // system text menu, which hides the segment menu (rename, assign).
            Text(segment.text)
                .simultaneousGesture(TapGesture(count: 2).onEnded { isEditing = true })
        }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        appModel.edit(segment, text: draft)
    }
}

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
        Button("Abschnitt kopieren", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(segment.text, forType: .string)
        }
        if let speaker = segment.speaker {
            Divider()
            Button("„\(speaker.displayName)“ umbenennen …", systemImage: "person.text.rectangle") {
                onRenameSpeaker(speaker)
            }
            let others = (speaker.transcript?.speakers ?? [])
                .filter { $0.id != speaker.id }
                // "Ich" first, then "Andere" and the numbered speakers.
                .sorted { ($0.role == .me ? 0 : 1, $0.number) < ($1.role == .me ? 0 : 1, $1.number) }
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
}

/// Small marker for manually corrected segments.
struct EditedMarker: View {
    var body: some View {
        Image(systemName: "pencil")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .help("Bearbeitet")
            .accessibilityLabel(Text("Bearbeitet"))
    }
}
