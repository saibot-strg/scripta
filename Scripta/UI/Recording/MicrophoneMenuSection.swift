import SwiftUI

/// The microphone choice as a menu section with a checkmark on the current one.
struct MicrophoneMenuSection: View {
    var title: LocalizedStringKey = "Mikrofon"

    var body: some View {
        Section(title) {
            MicrophonePicker()
                .pickerStyle(.inline)
                .labelsHidden()
        }
    }
}
