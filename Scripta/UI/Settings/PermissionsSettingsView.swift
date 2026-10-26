import AppKit
import AVFAudio
import SwiftUI

/// Settings › Berechtigungen: microphone, system audio, accessibility.
struct PermissionsSettingsView: View {
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var canPaste = TextInserter.canPostEvents

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    switch microphone {
                    case .granted:
                        Label("Erlaubt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .undetermined:
                        Button("Zugriff erlauben") {
                            Task {
                                _ = await AVAudioApplication.requestRecordPermission()
                                microphone = AVAudioApplication.shared.recordPermission
                            }
                        }
                    default:
                        openButton(.microphone)
                    }
                } label: {
                    Label("Mikrofon", systemImage: "mic")
                    Text("Für Aufnahmen und Meetings („Ich“).")
                }

                LabeledContent {
                    openButton(.systemAudio)
                } label: {
                    Label("Systemaudio", systemImage: "speaker.wave.2")
                    Text("Für Meetings („Andere“). macOS fragt beim ersten Meeting nach; der Status lässt sich nicht automatisch prüfen.")
                }

                LabeledContent {
                    if canPaste {
                        Label("Erlaubt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        openButton(.accessibility)
                    }
                } label: {
                    Label("Bedienungshilfen", systemImage: "keyboard")
                    Text("Für das Diktat: Text per ⌘V in andere Apps einfügen.")
                }
            } footer: {
                Text("Scripta arbeitet komplett lokal. Audio und Transkripte verlassen deinen Mac nicht.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphone = AVAudioApplication.shared.recordPermission
            canPaste = TextInserter.canPostEvents
        }
    }

    private func openButton(_ pane: PrivacyPane) -> some View {
        Button("Systemeinstellungen öffnen") {
            if let url = pane.url { NSWorkspace.shared.open(url) }
        }
    }
}
