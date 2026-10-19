import SwiftUI

/// Menu bar commands and keyboard shortcuts.
struct AppCommands: Commands {
    let appModel: AppModel

    var body: some Commands {
        let recorder = appModel.recorder
        let player = appModel.player

        CommandGroup(replacing: .appInfo) {
            Button("Über Scripta") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: AboutCredits.text])
                NSApp.activate()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Neue Aufnahme", systemImage: "record.circle") {
                Task { await appModel.startRecording() }
            }
            .keyboardShortcut("n")
            .disabled(recorder.isActive)

            Button(recorder.state == .paused ? "Aufnahme fortsetzen" : "Aufnahme pausieren",
                   systemImage: recorder.state == .paused ? "mic" : "pause") {
                appModel.togglePause()
            }
            .disabled(!recorder.isActive)

            Button("Aufnahme beenden", systemImage: "stop.circle") {
                appModel.stopRecording()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!recorder.isActive)

            Button("Neue Meeting-Aufnahme", systemImage: "person.2.wave.2") {
                Task { await appModel.startMeeting() }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(recorder.isActive)

            Divider()
            Button("Importieren …", systemImage: "square.and.arrow.down") {
                appModel.isImporterPresented = true
            }
            .keyboardShortcut("i")

            Divider()
            let exportable = appModel.selectedRecording.flatMap { recording in
                recording.transcript.map { $0.segments.isEmpty ? nil : recording } ?? nil
            }
            Button("Transkript kopieren", systemImage: "doc.on.doc") {
                if let exportable { appModel.copyTranscript(of: exportable) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(exportable == nil)
            Menu("Exportieren") {
                if let exportable {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            appModel.export(exportable, as: format)
                        } label: {
                            Text(format.label)
                        }
                    }
                }
            }
            .disabled(exportable == nil)
        }

        CommandMenu("Transkription") {
            Button("Ausgewählte transkribieren", systemImage: "text.bubble") {
                if let recording = appModel.selectedRecording { appModel.transcribe(recording) }
            }
            .keyboardShortcut("t")
            .disabled(appModel.selectedRecording.map { $0.status.isInProgress || appModel.library.audioURL(for: $0) == nil } ?? true)
            Button("Alle ausstehenden transkribieren", systemImage: "text.bubble.fill") {
                appModel.transcribeAllPending()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(appModel.pendingTranscriptionCount == 0)
        }

        // Placed before the standard text editing group so ⌘F always reaches the library search.
        CommandGroup(before: .textEditing) {
            Button("In Bibliothek suchen", systemImage: "magnifyingglass") {
                appModel.focusSearch()
            }
            .keyboardShortcut("f")
            Divider()
        }

        // Space toggles playback via a key monitor (see PlaybackSpaceShortcut);
        // a plain Space menu shortcut would swallow spaces typed into text fields.
        CommandMenu("Wiedergabe") {
            Button(player.isPlaying ? "Pause" : "Abspielen", systemImage: player.isPlaying ? "pause" : "play") {
                player.togglePlayPause()
            }
            .disabled(!player.isAvailable)
            Button("15 Sekunden zurück", systemImage: "gobackward.15") {
                player.skip(by: -PlayerModel.skipInterval)
            }
            .disabled(!player.isAvailable)
            Button("15 Sekunden vor", systemImage: "goforward.15") {
                player.skip(by: PlayerModel.skipInterval)
            }
            .disabled(!player.isAvailable)
        }

        #if DEBUG
        CommandMenu("Entwicklung") {
            Button("Beispieldaten einfügen") {
                appModel.perform { try appModel.library.insertSampleData() }
            }
            Button("Testton aufnehmen (ohne Mikrofon)") {
                appModel.recorder.usesTestTone = true
                Task { await appModel.startRecording() }
            }
            .disabled(recorder.isActive)
            Button("Test-Meeting aufnehmen (zwei Testtöne)") {
                appModel.recorder.usesTestTone = true
                Task { await appModel.startMeeting(.allSystemAudio) }
            }
            .disabled(recorder.isActive)
            Button("Bibliothek leeren", role: .destructive) {
                appModel.selectedRecordingID = nil
                appModel.perform { try appModel.library.deleteAll() }
            }
        }
        #endif
    }
}
