import AppKit
import SwiftUI

/// One row in the recording list: title and date, below them the length and
/// the number of voices, or what is still open.
struct RecordingRow: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording
    /// Under a date heading the row shows the time, otherwise the date.
    var isUnderDateHeading = false
    /// Set while this row's title is being edited: called with the new title,
    /// or nil when the edit was cancelled.
    var onRename: ((String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let onRename {
                    RowTitleEditor(title: recording.title, onFinish: onRename)
                } else {
                    Text(recording.title)
                        .font(.headline)
                        .foregroundStyle(Color.rowTitle)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(isUnderDateHeading ? Formatters.rowDate(recording.createdAt) : Formatters.listDate(recording.createdAt))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.rowDetail)
                    .layoutPriority(1)
            }
            detailLine
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detailLine: some View {
        let length = Formatters.shortDuration(recording.duration)
        switch recording.status {
        case .done:
            let voices = recording.transcript?.speakers.count ?? 0
            Group {
                if voices > 1 {
                    Text("\(length) · \(voices) Stimmen")
                } else {
                    Text(verbatim: length)
                }
            }
            .foregroundStyle(Color.rowDetail)
        case .notTranscribed:
            Text("\(length) · Noch kein Transkript")
                .foregroundStyle(Color.rowDetail)
        case .queued:
            Text("In der Warteschlange")
                .foregroundStyle(Color.processing)
        case .running:
            let progress = appModel.transcription.progress[recording.id] ?? 0
            Text(progress > 0 ? "Wird transkribiert · \(progress.formatted(.percent.precision(.fractionLength(0))))" : "Wird transkribiert …")
                .monospacedDigit()
                .foregroundStyle(Color.processing)
        case .failed:
            Text("Transkription fehlgeschlagen")
                .foregroundStyle(Color.red)
        }
    }
}

/// The title as a text field in place, with everything selected, as when
/// renaming in the Finder. Return or a click elsewhere takes the new title,
/// Escape keeps the old one.
private struct RowTitleEditor: View {
    let title: String
    let onFinish: (String?) -> Void
    @State private var draft = ""
    @State private var selection: TextSelection?
    @State private var isFinished = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Titel", text: $draft, selection: $selection)
            .textFieldStyle(.plain)
            .font(.headline)
            .foregroundStyle(Color.rowTitle)
            .focused($isFocused)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            // The text stays where the title was; the field's frame grows around it.
            .padding(.horizontal, -4)
            .padding(.vertical, -2)
            .onAppear {
                draft = title
                selection = TextSelection(range: draft.startIndex..<draft.endIndex)
                isFocused = true
            }
            .onSubmit { finish(with: draft) }
            .onExitCommand { finish(with: nil) }
            .onChange(of: isFocused) { _, focused in
                if !focused { finish(with: draft) }
            }
    }

    private func finish(with title: String?) {
        guard !isFinished else { return }
        isFinished = true
        onFinish(title)
    }
}

extension Color {
    /// Text colors of the list rows. Fixed label colors on purpose: the chosen
    /// row is only tinted, so its text must not turn white as it would on the
    /// system's filled selection.
    static let rowTitle = Color(nsColor: .labelColor)
    static let rowDetail = Color(nsColor: .secondaryLabelColor)
}
