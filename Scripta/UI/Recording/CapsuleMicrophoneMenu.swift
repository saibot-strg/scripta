import SwiftUI

/// Switches the microphone without stopping the recording.
struct CapsuleMicrophoneMenu: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.microphone) private var microphone = ""

    var body: some View {
        Menu {
            MicrophoneMenuSection()
        } label: {
            Label("Mikrofon", systemImage: "waveform.and.mic")
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .fixedSize()
        .help("Mikrofon wechseln (aktiv: \(appModel.microphoneName(forUID: microphone) ?? "–"))")
    }
}
