import AppKit
import SwiftUI

/// Settings › Aufnahme: microphone, file format, meetings, storage location.
struct RecordingSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.recordingFormat) private var format: RecordingFileFormat = .aac
    @AppStorage(SettingsKey.recordingQuality) private var quality: RecordingQuality = .standard
    @AppStorage(SettingsKey.meetingSource) private var meetingSource = ""
    @AppStorage(SettingsKey.levelsMicrophone) private var levelsMicrophone = true
    @State private var apps: [MeetingApp] = []

    var body: some View {
        let locations = appModel.library.locations
        Form {
            Section {
                MicrophonePicker()
                Toggle(isOn: $levelsMicrophone) {
                    Text("Leises Mikrofon anheben")
                    Text("Bringt deine Stimme nach der Aufnahme auf normale Lautstärke, etwa bei leisen Headsets.")
                }
            } footer: {
                Text("Gilt für Aufnahmen, Meetings („Ich“) und das Diktat.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Format", selection: $format) {
                    ForEach(RecordingFileFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("Qualität", selection: $quality) {
                    ForEach(RecordingQuality.allCases) { Text($0.label).tag($0) }
                }
                .disabled(format != .aac)
            } footer: {
                Text("Während der Aufnahme wird verlustfrei und absturzsicher gespeichert. Danach wird die Datei im gewählten Format abgelegt. Für die Transkription spielt das Format keine Rolle.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Standard-Quelle", selection: $meetingSource) {
                    Text("Gesamtes Systemaudio").tag("")
                    if !meetingSource.isEmpty, !apps.contains(where: { $0.bundleID == meetingSource }) {
                        // Keep the stored choice visible while that app isn't running.
                        Text(meetingSource).tag(meetingSource)
                    }
                    ForEach(apps) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
            } header: {
                Text("Meetings")
            } footer: {
                Text("Mikrofon („Ich“) und Systemaudio („Andere“) werden als getrennte Spuren aufgenommen. Mit Kopfhörern bleiben die Spuren am saubersten getrennt.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Neue Aufnahmen") {
                    Text(locations.current.rootURL.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Ändern …", action: appModel.chooseStorageFolder)
                    if !locations.isDefault {
                        Button("Standard verwenden", action: appModel.useDefaultStorage)
                    }
                    Spacer()
                    Button("Im Finder zeigen", action: revealStorageFolder)
                }
                .disabled(appModel.recorder.isActive)
            } header: {
                Text("Speicherort")
            } footer: {
                Text("Bestehende Aufnahmen bleiben, wo sie sind. Ordner in iCloud Drive oder auf externen Platten funktionieren, solange sie verfügbar sind.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .task {
            apps = AudioAppCatalog.availableApps()
            appModel.refreshMicrophones()
        }
    }

    private func revealStorageFolder() {
        let url = appModel.library.locations.current.rootURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
