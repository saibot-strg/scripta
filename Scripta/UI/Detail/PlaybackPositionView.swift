import SwiftUI

/// Elapsed time, position slider and duration of the player.
struct PlaybackPositionView: View {
    @Bindable var player: PlayerModel

    var body: some View {
        Text(Formatters.timestamp(player.currentTime))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, alignment: .trailing)

        Slider(value: $player.position, in: 0...max(player.duration, 0.1), onEditingChanged: scrubbingChanged)
            .controlSize(.small)
            .accessibilityLabel(Text("Position"))
            .accessibilityValue(Text(Formatters.spokenDuration(player.currentTime)))

        Text(Formatters.timestamp(player.duration))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, alignment: .leading)
    }

    private func scrubbingChanged(_ isEditing: Bool) {
        isEditing ? player.beginScrubbing() : player.endScrubbing()
    }
}
