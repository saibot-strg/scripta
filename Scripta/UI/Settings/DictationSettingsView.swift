import AppKit
import SwiftUI

/// Settings › Diktat: system-wide push-to-talk.
struct DictationSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(DictationSettings.enabledKey) private var isEnabled = false
    @AppStorage(DictationSettings.modeKey) private var mode: DictationController.Mode = .hold
    @AppStorage(DictationSettings.appendsSpaceKey) private var appendsSpace = true
    @AppStorage(DictationSettings.playsSoundsKey) private var playsSounds = false
    @State private var shortcut = DictationSettings.shortcut
    @State private var canPaste = TextInserter.canPostEvents
    @State private var trial = ""

    var body: some View {
        let dictation = appModel.dictation
        Form {
            Section {
                Toggle("Diktat in allen Apps", isOn: $isEnabled)
            } footer: {
                Text("Kürzel halten, sprechen, loslassen: Der Text erscheint dort, wo der Cursor steht – in jeder App. Das Audio bleibt nur im Arbeitsspeicher und wird nicht gespeichert.")
                    .foregroundStyle(.secondary)
            }

            Section("Bedienung") {
                LabeledContent("Tastenkürzel") {
                    ShortcutRecorder(shortcut: $shortcut) { isRecording in
                        dictation.setShortcutSuspended(isRecording)
                    }
                }
                if let error = dictation.registrationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Picker("Modus", selection: $mode) {
                    ForEach(DictationController.Mode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Leerzeichen nach dem Text", isOn: $appendsSpace)
                Toggle(isOn: $playsSounds) {
                    Text("Ton bei Start und Ende")
                    Text("Ein leiser Ton, damit du hörst, wann das Diktat läuft. Mit Lautsprechern kann das Mikrofon den Startton mit aufnehmen.")
                }
            }
            .disabled(!isEnabled)

            Section {
                LabeledContent {
                    if canPaste {
                        Label("Erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        HStack {
                            Button("Erlauben") {
                                TextInserter.requestPostEventAccess()
                                canPaste = TextInserter.canPostEvents
                            }
                            Button("Systemeinstellungen öffnen") {
                                if let url = PrivacyPane.accessibility.url { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                } label: {
                    Label("Text in andere Apps einfügen", systemImage: "keyboard")
                    Text("Unter „Bedienungshilfen“. Ohne diese Freigabe landet der Text in der Zwischenablage.")
                }
            } header: {
                Text("Berechtigung")
            }

            Section {
                TextField("Hier ausprobieren: Kürzel halten und sprechen", text: $trial, axis: .vertical)
                    .lineLimit(3...6)
                if let latency = dictation.lastLatency {
                    LabeledContent("Letztes Diktat") {
                        Text("\(latency.formatted(.units(allowed: [.milliseconds], width: .narrow))) nach dem Loslassen")
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Ausprobieren")
            } footer: {
                Text("Für sofortige Ergebnisse bleibt das Sprachmodell geladen, solange das Diktat aktiv ist (einige hundert MB Arbeitsspeicher).")
                    .foregroundStyle(.secondary)
            }
            .disabled(!isEnabled)
        }
        .formStyle(.grouped)
        .frame(height: 600)
        .onChange(of: isEnabled) { dictation.applySettings() }
        .onChange(of: shortcut) {
            DictationSettings.shortcut = shortcut
            dictation.applySettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canPaste = TextInserter.canPostEvents
        }
    }
}
