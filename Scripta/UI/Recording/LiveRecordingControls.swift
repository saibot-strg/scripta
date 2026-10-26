import SwiftUI

/// Pause/continue and stop, the same actions as the capsule below the list.
struct LiveRecordingControls: View {
    @Environment(AppModel.self) private var appModel
    let isPaused: Bool
    let isStarting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(isPaused ? "Fortsetzen" : "Pausieren", systemImage: isPaused ? "mic.fill" : "pause.fill", action: appModel.togglePause)
                .buttonStyle(.bordered)
            Button("Aufnahme beenden", systemImage: "stop.fill", action: stop)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .controlSize(.large)
        .disabled(isStarting)
    }

    private func stop() {
        appModel.stopRecording()
    }
}
