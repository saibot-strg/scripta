import SwiftUI

/// The scrolling levels of the running recording on one card: a lane for
/// "Ich" and one for "Andere" in a meeting, a single lane otherwise.
struct LiveRecordingLevels: View {
    let recorder: AudioRecorder
    let isMeeting: Bool
    let isPaused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isMeeting {
                lane("Ich", track: .microphone, tint: .recording)
                Divider()
                lane("Andere", track: .system, tint: .brandSky)
            } else {
                LiveLevelMeter(recorder: recorder, tint: isPaused ? .secondary : .recording)
                    .frame(height: 64)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .accessibilityHidden(true)
    }

    private func lane(_ label: LocalizedStringKey, track: LiveLevelMeter.Track, tint: Color) -> some View {
        let color = isPaused ? Color.secondary : tint
        return HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.callout.weight(.semibold))
            }
            .frame(width: 76, alignment: .leading)

            LiveLevelMeter(recorder: recorder, track: track, tint: color)
                .frame(height: 56)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
