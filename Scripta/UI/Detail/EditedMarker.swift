import SwiftUI

/// Small marker for manually corrected segments.
struct EditedMarker: View {
    var body: some View {
        Image(systemName: "pencil")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .help("Bearbeitet")
            .accessibilityLabel(Text("Bearbeitet"))
    }
}
