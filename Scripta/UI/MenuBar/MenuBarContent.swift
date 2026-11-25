import AppKit
import SwiftUI

/// The menu bar window: two large buttons to start recording, or the running
/// recording with pause and stop; below them the microphone and the app.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowVisible) private var isWindowVisible
    @AppStorage(DictationSettings.enabledKey) private var isDictationEnabled = false
    @AppStorage(DictationSettings.shortcutKey) private var shortcutData: Data?
    /// The window this view sits in, to close it after an action.
    @State private var window = WeakWindow()

    var body: some View {
        let recorder = appModel.recorder

        VStack(alignment: .leading, spacing: 12) {
            if recorder.isActive {
                running(recorder)
            } else {
                HStack(spacing: 8) {
                    Button(action: startRecording) {
                        MenuBarTile(title: "Aufnahme", shortcut: "⌘N") {
                            LogoBarsShape(levels: [1, 1, 1, 1])
                                .frame(width: 18, height: 18)
                        }
                    }
                    .buttonStyle(MenuBarTileStyle(isProminent: true))

                    Button(action: startMeeting) {
                        MenuBarTile(title: "Meeting", shortcut: "⇧⌘N") {
                            Image(systemName: "person.2.wave.2")
                                .foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(MenuBarTileStyle(isProminent: false))
                    .contextMenu { MeetingSourceMenu() }
                    .help("Meeting aufnehmen: Mikrofon und Systemaudio getrennt (⇧⌘N)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mikrofon")
                    Spacer(minLength: 8)
                    MicrophonePicker()
                        .labelsHidden()
                        .frame(maxWidth: 190)
                        .fixedSize()
                }
                Group {
                    if isDictationEnabled {
                        Text("Diktat: \(shortcut.displayString) halten")
                    } else {
                        Text("Diktat ist ausgeschaltet")
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if let update = appModel.updates.availableUpdate {
                Button("Scripta \(update.version.description) herunterladen …") {
                    appModel.updates.openReleasePage(for: update)
                    close()
                }
                .buttonStyle(.link)
                .padding(.horizontal, 4)
            }

            Divider()

            HStack(spacing: 6) {
                Button("Scripta öffnen", action: showMainWindow)
                    .frame(maxWidth: .infinity)
                Button("Einstellungen …", action: showSettings)
                    .frame(maxWidth: .infinity)
                Button("Scripta beenden", systemImage: "power", action: quit)
                    .labelStyle(.iconOnly)
                    .help("Scripta beenden")
            }
            .controlSize(.large)
        }
        .padding(12)
        .frame(width: 300)
        .background(WindowReader { window.value = $0 })
    }

    @ViewBuilder
    private func running(_ recorder: AudioRecorder) -> some View {
        let isPaused = recorder.state == .paused

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Group {
                    if isPaused {
                        Image(systemName: "pause.fill")
                            .font(.caption2.weight(.bold))
                    } else {
                        RecordingDot(isPulsing: !reduceMotion && isWindowVisible)
                            .foregroundStyle(.recording)
                    }
                }
                .frame(width: 10)
                .accessibilityHidden(true)
                if isPaused {
                    Text("Pausiert")
                } else {
                    Text(recorder.isMeeting ? "Meeting läuft" : "Aufnahme läuft")
                }
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                RecordingTimerText(recorder: recorder, animatesDigits: false)
                    .font(.system(size: 30, weight: .light))
                Spacer(minLength: 8)
                LiveLevelMeter(recorder: recorder, tint: isPaused ? .secondary : .accentColor, barWidth: 2, spacing: 2)
                    .frame(width: 110, height: 28)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)

        HStack(spacing: 8) {
            Button(action: appModel.togglePause) {
                Label(isPaused ? "Fortsetzen" : "Pause", systemImage: isPaused ? "mic.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            Button(action: stopRecording) {
                Label {
                    Text("Beenden")
                } icon: {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.recording)
                }
                .frame(maxWidth: .infinity)
            }
            .help("Aufnahme beenden und speichern")
        }
        .controlSize(.extraLarge)
        .disabled(recorder.state == .starting)
    }

    private var shortcut: KeyShortcut {
        shortcutData.flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) } ?? .defaultDictation
    }

    private func startRecording() {
        Task { await appModel.startRecording() }
        close()
    }

    private func startMeeting() {
        Task { await appModel.startMeeting() }
        close()
    }

    private func stopRecording() {
        appModel.stopRecording()
        close()
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
        close()
    }

    private func showSettings() {
        openSettings()
        NSApp.activate()
        close()
    }

    private func quit() {
        NSApp.terminate(nil)
    }

    /// Closes the menu bar window after an action. SwiftUI's own way first, so
    /// the menu bar icon knows about it; the window itself as a fallback.
    private func close() {
        dismiss()
        let window = window.value
        Task {
            if window?.isVisible == true { window?.close() }
        }
    }
}

/// Icon on top, title and shortcut below, as on a large key.
private struct MenuBarTile<Icon: View>: View {
    let title: LocalizedStringKey
    let shortcut: String
    @ViewBuilder var icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            icon
                .font(.title3)
                .frame(height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.semibold)
                Text(verbatim: shortcut)
                    .font(.callout)
                    .opacity(0.75)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Filled with the accent color for the main action, quiet otherwise.
private struct MenuBarTileStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(12)
            .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isProminent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
