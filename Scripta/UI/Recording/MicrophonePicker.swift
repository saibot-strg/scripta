import SwiftUI

/// Microphone choice: the system default plus every connected input. Shared
/// by the settings and the recording menus (there with `.inline` style);
/// choosing one during a recording switches the recording over.
struct MicrophonePicker: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.microphone) private var microphone = ""

    var body: some View {
        // A custom binding on purpose: choosing also switches a running recording.
        Picker("Mikrofon", selection: Binding(get: { microphone }, set: { appModel.selectMicrophone($0) })) {
            if let name = appModel.defaultMicrophone?.name {
                Text("Systemstandard (\(name))").tag("")
            } else {
                Text("Systemstandard").tag("")
            }
            if !microphone.isEmpty, !appModel.microphones.contains(where: { $0.uid == microphone }) {
                Text("Nicht verbunden").tag(microphone)
            }
            ForEach(appModel.microphones) { Text($0.name).tag($0.uid) }
        }
    }
}
