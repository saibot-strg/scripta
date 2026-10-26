import SwiftUI

/// The icon shows when something is being recorded.
struct MenuBarLabel: View {
    let recorder: AudioRecorder

    var body: some View {
        Image(systemName: recorder.isActive ? "record.circle" : "waveform")
            .accessibilityLabel(Text(recorder.isActive ? "Scripta – Aufnahme läuft" : "Scripta"))
    }
}
