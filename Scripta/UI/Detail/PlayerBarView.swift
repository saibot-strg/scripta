import SwiftUI

/// Floating Liquid Glass player bar at the bottom of the detail view.
struct PlayerBarView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let player = appModel.player

        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 14) {
                    PlaybackTransportButtons(player: player)
                    // Only this part follows the playback position (20 times per second).
                    PlaybackPositionView(player: player)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title3)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

                PlaybackRateMenu(player: player)
            }
        }
        .disabled(!player.isAvailable)
        .help(player.isAvailable ? Text(verbatim: "") : Text("Für diese Aufnahme gibt es keine Audiodatei."))
    }
}
