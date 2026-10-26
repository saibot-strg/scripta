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
