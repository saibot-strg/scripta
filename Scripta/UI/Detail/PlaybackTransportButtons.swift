import SwiftUI

/// Back 15 s, play/pause, forward 15 s.
struct PlaybackTransportButtons: View {
    let player: PlayerModel

    var body: some View {
        Button("15 Sekunden zurück", systemImage: "gobackward.15", action: skipBack)
        Button(player.isPlaying ? "Pause" : "Wiedergabe", systemImage: player.isPlaying ? "pause.fill" : "play.fill", action: player.togglePlayPause)
            .font(.title2)
            .contentTransition(.symbolEffect(.replace))
            .help("Wiedergabe starten oder pausieren (Leertaste)")
        Button("15 Sekunden vor", systemImage: "goforward.15", action: skipForward)
    }

    private func skipBack() {
        player.skip(by: -PlayerModel.skipInterval)
    }

    private func skipForward() {
        player.skip(by: PlayerModel.skipInterval)
    }
}
