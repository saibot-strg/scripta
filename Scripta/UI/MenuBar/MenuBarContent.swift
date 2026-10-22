import AppKit
import SwiftUI

/// Menu bar icon: quick start and stop, also with the main window closed.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let recorder = appModel.recorder

        if recorder.isActive {
            let duration = Formatters.duration(recorder.duration)
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
        if DictationSettings.isEnabled {
            Text("Diktat: \(DictationSettings.shortcut.displayString) halten")
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
}

/// The icon shows when something is being recorded.
struct MenuBarLabel: View {
    let recorder: AudioRecorder

    var body: some View {
        Image(systemName: recorder.isActive ? "record.circle" : "waveform")
            .accessibilityLabel(Text(recorder.isActive ? "Scripta – Aufnahme läuft" : "Scripta"))
    }
}
