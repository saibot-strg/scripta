import AppKit
import SwiftUI

/// Menu bar icon: quick start and stop, also with the main window closed.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    // Observed so the dictation line follows changes in the settings.
    @AppStorage(DictationSettings.enabledKey) private var isDictationEnabled = false
    @AppStorage(DictationSettings.shortcutKey) private var shortcutData: Data?

    var body: some View {
        let recorder = appModel.recorder

        if recorder.isActive {
            // Whole seconds: the menu is rebuilt on every change it reads.
            let duration = Formatters.duration(TimeInterval(recorder.elapsedSeconds))
            Text(recorder.isMeeting ? "Meeting läuft · \(duration)" : "Aufnahme läuft · \(duration)")
            Button(recorder.state == .paused ? "Aufnahme fortsetzen" : "Aufnahme pausieren") {
                appModel.togglePause()
            }
            .disabled(recorder.state == .starting)
            Button("Aufnahme beenden") {
                appModel.stopRecording()
            }
        } else {
            Button("Neue Aufnahme") {
                Task { await appModel.startRecording() }
            }
            Button("Meeting aufnehmen") {
                Task { await appModel.startMeeting() }
            }
            Menu("Meeting aufnehmen mit") {
                MeetingSourceMenu()
            }
        }
        Menu("Mikrofon") {
            MicrophonePicker()
                .pickerStyle(.inline)
                .labelsHidden()
        }

        Divider()
        if isDictationEnabled {
            Text("Diktat: \(shortcut.displayString) halten")
        } else {
            Text("Diktat ist ausgeschaltet")
        }

        Divider()
        if let update = appModel.updates.availableUpdate {
            Button("Scripta \(update.version.description) herunterladen …") {
                appModel.updates.openReleasePage(for: update)
            }
        }
        Button("Scripta öffnen") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink {
            Text("Einstellungen …")
        }
        Divider()
        Button("Scripta beenden") {
            NSApp.terminate(nil)
        }
    }

    private var shortcut: KeyShortcut {
        shortcutData.flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) } ?? .defaultDictation
    }
}
