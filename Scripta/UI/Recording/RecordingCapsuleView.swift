import SwiftUI

/// Floating Liquid Glass controls for the active recording.
struct RecordingCapsuleView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        let recorder = appModel.recorder
        let isRunning = recorder.state == .recording || recorder.state == .paused

        VStack(spacing: 8) {
            if recorder.isSystemAudioMissing {
                SystemAudioHint()
                    .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                // Status, microphone and pause share one glass container: the
                // buttons grow out of the status capsule when recording starts.
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 10) {
                        RecordingCapsuleStatus(recorder: recorder)
                            .padding(.leading, 14)
                            .padding(.trailing, 12)
                            .frame(minHeight: 44)
                            .glassEffect(.regular, in: .capsule)
                            .glassEffectID("status", in: glass)

                        if isRunning {
                            CapsuleMicrophoneMenu()
                                .glassEffectID("microphone", in: glass)
                            pauseButton(isPaused: recorder.state == .paused)
                                .glassEffectID("pause", in: glass)
                        }
                    }
                }

                if recorder.isActive {
                    stopButton(isEnabled: recorder.state != .starting)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: isRunning)
        .animation(.smooth, value: recorder.isSystemAudioMissing)
    }

    private func pauseButton(isPaused: Bool) -> some View {
        Button(action: appModel.togglePause) {
            Label(isPaused ? "Fortsetzen" : "Pausieren", systemImage: isPaused ? "mic.fill" : "pause.fill")
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help(isPaused ? "Aufnahme fortsetzen" : "Aufnahme pausieren")
    }

    private func stopButton(isEnabled: Bool) -> some View {
        Button(action: stopRecording) {
            Label("Aufnahme beenden", systemImage: "stop.fill")
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(.red)
        .controlSize(.large)
        .disabled(!isEnabled)
        .help("Aufnahme beenden und speichern (⌘↩)")
    }

    private func stopRecording() {
        appModel.stopRecording()
    }
}
