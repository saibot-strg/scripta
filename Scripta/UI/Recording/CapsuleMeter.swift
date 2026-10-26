import SwiftUI

/// A small level meter with its track's name, for meetings in the capsule.
struct CapsuleMeter: View {
    let label: LocalizedStringKey
    let recorder: AudioRecorder
    let track: LiveLevelMeter.Track
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            LiveLevelMeter(recorder: recorder, track: track, tint: tint, barWidth: 2, spacing: 1.5)
                .frame(height: 12)
        }
    }
}
