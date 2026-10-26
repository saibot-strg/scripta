import SwiftUI

/// Right-click menu of a recording in the list.
struct RecordingContextMenu: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording
    let folders: [Folder]
    @Binding var renameTarget: Recording?
    @Binding var renameText: String
    @Binding var deleteTarget: Recording?

    var body: some View {
        let hasAudio = appModel.library.audioURL(for: recording) != nil

        Button("Abspielen", systemImage: "play") {
            appModel.play(recording)
        }
        .disabled(!hasAudio)
        if recording.status.isInProgress {
            Button("Transkription abbrechen", systemImage: "xmark.circle") {
                appModel.cancelTranscription(of: recording)
            }
        } else {
            Button(recording.status == .done ? "Erneut transkribieren" : "Transkribieren", systemImage: "text.bubble") {
                appModel.requestTranscription(of: recording)
            }
            .disabled(!hasAudio)
        }
        Divider()
        Button("Umbenennen …", systemImage: "pencil", action: rename)
        if recording.transcript.map({ !$0.segments.isEmpty }) == true {
            Button("Transkript kopieren", systemImage: "doc.on.doc") {
                appModel.copyTranscript(of: recording)
            }
            Menu("Exportieren", systemImage: "square.and.arrow.up") {
                ExportMenuItems(recording: recording)
            }
        }
        Menu("In Ordner", systemImage: "folder.badge.plus") {
            ForEach(folders) { folder in
                Button(folder.name) { appModel.move(recordingIDs: [recording.id], to: folder) }
                    .disabled(recording.folder?.id == folder.id)
            }
            if recording.folder != nil {
                Divider()
                Button("Aus dem Ordner nehmen") { appModel.move(recordingIDs: [recording.id], to: nil) }
            }
            if folders.isEmpty {
                Text("Noch keine Ordner – lege sie links mit + an.")
            }
        }
        Button("Im Finder zeigen", systemImage: "folder") {
            appModel.revealInFinder(recording)
        }
        .disabled(!hasAudio)
        Divider()
        Button("Löschen …", systemImage: "trash", role: .destructive) {
            deleteTarget = recording
        }
    }

    private func rename() {
        renameText = recording.title
        renameTarget = recording
    }
}
