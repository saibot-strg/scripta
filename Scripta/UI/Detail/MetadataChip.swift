import SwiftUI

/// Small rounded label for a single piece of metadata.
struct MetadataChip<Content: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        Label {
            content
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.fill.tertiary, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
