import SwiftUI

/// Sidebar note when a newer Scripta is available on GitHub.
struct UpdateFooter: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let updates = appModel.updates
        if let update = updates.availableUpdate {
            VStack(alignment: .leading, spacing: 6) {
                Label("Scripta \(update.version.description) ist verfügbar", systemImage: "arrow.down.app")
                    .font(.caption.weight(.semibold))
                Text("Du verwendest Version \(updates.currentVersion.description).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Herunterladen") { updates.openReleasePage(for: update) }
                    Button("Überspringen") { updates.skip(update) }
                        .help("Erst bei der nächsten Version wieder hinweisen")
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
