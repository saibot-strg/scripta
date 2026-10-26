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
