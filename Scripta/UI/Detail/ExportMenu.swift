import SwiftUI

/// Export formats, copy and share — used in the toolbar, the list's context
/// menu and the File menu.
struct ExportMenuItems: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    var body: some View {
        ForEach(ExportFormat.allCases) { format in
            Button {
                appModel.export(recording, as: format)
            } label: {
                Text(format.label)
            }
        }
        Divider()
        Button("Transkript kopieren", systemImage: "doc.on.doc") {
            appModel.copyTranscript(of: recording)
        }
        if let text = appModel.shareText(for: recording) {
            ShareLink(item: text, subject: Text(recording.title)) {
                Label("Teilen …", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// Brief confirmation at the bottom of the window.
struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .accessibilityAddTraits(.isStaticText)
    }
}
