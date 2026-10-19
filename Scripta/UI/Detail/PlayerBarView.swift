import SwiftUI

/// Floating Liquid Glass player bar at the bottom of the detail view.
struct PlayerBarView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let player = appModel.player

        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                transport(player)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)

                rateMenu(player)
            }
        }
        .disabled(!player.isAvailable)
        .help(player.isAvailable ? Text(verbatim: "") : Text("Für diese Aufnahme gibt es keine Audiodatei."))
    }

    private func transport(_ player: PlayerModel) -> some View {
        HStack(spacing: 14) {
            Button("15 Sekunden zurück", systemImage: "gobackward.15") {
                player.skip(by: -PlayerModel.skipInterval)
            }
            Button(player.isPlaying ? "Pause" : "Wiedergabe", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                player.togglePlayPause()
            }
            .font(.title2)
            .contentTransition(.symbolEffect(.replace))
            .help("Wiedergabe starten oder pausieren (Leertaste)")
            Button("15 Sekunden vor", systemImage: "goforward.15") {
                player.skip(by: PlayerModel.skipInterval)
            }

            Text(Formatters.timestamp(player.currentTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { time in
                        if player.isScrubbing { player.scrub(to: time) } else { player.seek(to: time) }
                    }
                ),
                in: 0...max(player.duration, 0.1),
                onEditingChanged: { editing in
                    editing ? player.beginScrubbing() : player.endScrubbing()
                }
            )
            .controlSize(.small)
            .accessibilityLabel(Text("Position"))
            .accessibilityValue(Text(Formatters.spokenDuration(player.currentTime)))

            Text(Formatters.timestamp(player.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
    }

    private func rateMenu(_ player: PlayerModel) -> some View {
        @Bindable var player = player
        return Menu {
            Picker("Tempo", selection: $player.rate) {
                ForEach(PlayerModel.rates, id: \.self) { rate in
                    Text("\(rate, format: .number.precision(.fractionLength(0...2)))×").tag(rate)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("\(player.rate, format: .number.precision(.fractionLength(0...2)))×")
                .monospacedDigit()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .help("Wiedergabetempo")
    }
}
