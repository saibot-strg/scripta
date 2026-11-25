import SwiftUI

/// Microphone, stop and pause as round buttons below the levels.
struct LiveRecordingControls: View {
    @Environment(AppModel.self) private var appModel
    let isPaused: Bool
    let isStarting: Bool

    var body: some View {
        HStack(spacing: 18) {
            Menu {
                MicrophoneMenuSection()
            } label: {
                Label("Mikrofon", systemImage: "mic")
                    .labelStyle(.iconOnly)
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .fixedSize()
            .help("Mikrofon wechseln")

            Button(action: stop) {
                Label("Aufnahme beenden", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.recording)
            .help("Aufnahme beenden und speichern (⌘↩)")

            Button(action: appModel.togglePause) {
                Label(isPaused ? "Fortsetzen" : "Pausieren", systemImage: isPaused ? "mic.fill" : "pause.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(isPaused ? "Aufnahme fortsetzen" : "Aufnahme pausieren")
        }
        .controlSize(.extraLarge)
        .disabled(isStarting)
    }

    private func stop() {
        appModel.stopRecording()
    }
}
