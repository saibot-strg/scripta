import SwiftUI

/// A level meter with its track's name ("Ich", "Andere") in front.
struct LabeledLevelMeter: View {
    let label: LocalizedStringKey
    let recorder: AudioRecorder
    let track: LiveLevelMeter.Track
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            LiveLevelMeter(recorder: recorder, track: track, tint: tint)
                .frame(height: 28)
        }
    }
}
