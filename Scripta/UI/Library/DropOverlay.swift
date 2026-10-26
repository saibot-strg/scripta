import SwiftUI

/// Shown while files are dragged over the window.
struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 24))
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(Color.accentColor)
                    Text("Zum Importieren loslassen")
                        .font(.title3.weight(.semibold))
                    Text("Audio und Video – bei Videos wird nur die Tonspur übernommen.")
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
            .padding(16)
            .allowsHitTesting(false)
    }
}
