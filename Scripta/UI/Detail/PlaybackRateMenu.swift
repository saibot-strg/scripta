import SwiftUI

/// Playback speed, shown as "1×" next to the player.
struct PlaybackRateMenu: View {
    @Bindable var player: PlayerModel

    var body: some View {
        Menu {
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
        .accessibilityLabel(Text("Wiedergabetempo"))
    }
}
