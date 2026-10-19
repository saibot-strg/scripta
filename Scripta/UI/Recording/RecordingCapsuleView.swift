import AppKit
import SwiftUI

/// Floating Liquid Glass controls for the active recording.
struct RecordingCapsuleView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let recorder = appModel.recorder

        VStack(spacing: 8) {
            if recorder.isSystemAudioMissing {
                SystemAudioHint()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                // Status and pause share one glass container so they blend when
                // they animate; the tinted stop button stays separate.
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 10) {
                        status(recorder: recorder)
                            .padding(.leading, 14)
                            .padding(.trailing, 12)
                            .frame(minHeight: 44)
                            .glassEffect(.regular, in: .capsule)

                        if recorder.state == .recording || recorder.state == .paused {
                            pauseButton(isPaused: recorder.state == .paused)
                        }
                    }
                }

                if recorder.isActive {
                    stopButton(isEnabled: recorder.state != .starting)
                }
            }
        }
        .animation(.smooth, value: recorder.isSystemAudioMissing)
    }

    // MARK: - Status

    @ViewBuilder
    private func status(recorder: AudioRecorder) -> some View {
        if appModel.isSavingRecording {
            Label {
                Text("Meeting wird gespeichert …")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.callout.weight(.medium))
        } else if recorder.state == .starting {
            Label {
                Text(recorder.isMeeting ? "Systemaudio wird verbunden …" : "Aufnahme startet …")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.callout.weight(.medium))
        } else {
            let isPaused = recorder.state == .paused
            HStack(spacing: 10) {
                Image(systemName: isPaused ? "pause.circle.fill" : "circle.fill")
                    .font(isPaused ? .body : .caption)
                    .foregroundStyle(isPaused ? Color.secondary : Color.red)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isPaused)
                    .frame(width: 16)

                Text(Formatters.duration(recorder.duration))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .frame(minWidth: 52, alignment: .leading)

                if recorder.isMeeting {
                    VStack(spacing: 3) {
                        meter(label: "Ich", levels: recorder.levels, tint: isPaused ? .secondary : .red)
                        meter(label: "Andere", levels: recorder.systemLevels, tint: isPaused ? .secondary : .green)
                    }
                    .padding(.vertical, 6)
                } else {
                    LevelMeterView(levels: recorder.levels, tint: isPaused ? .secondary : .red)
                        .frame(height: 24)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isPaused ? "Aufnahme pausiert" : "Aufnahme läuft"))
            .accessibilityValue(Text(Formatters.spokenDuration(recorder.duration)))
        }
    }

    private func meter(label: LocalizedStringKey, levels: [Float], tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            LevelMeterView(levels: levels, tint: tint, barWidth: 2, spacing: 1.5)
                .frame(height: 12)
        }
    }

    // MARK: - Buttons

    private func pauseButton(isPaused: Bool) -> some View {
        Button {
            appModel.togglePause()
        } label: {
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
        Button {
            appModel.stopRecording()
        } label: {
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
}

/// Shown when apps play sound but the meeting's system track stays silent.
private struct SystemAudioHint: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kein Systemton")
                    .font(.callout.weight(.semibold))
                Text("Erlaube Scripta die Systemaudio-Aufnahme und starte das Meeting neu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Öffnen") {
                if let url = PrivacyPane.systemAudio.url { NSWorkspace.shared.open(url) }
            }
            .help("Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
