import SwiftUI

/// Progress and result of an import, above the recording list.
struct ImportStatusView: View {
    @Environment(AppModel.self) private var appModel
    let status: AppModel.ImportStatus

    var body: some View {
        HStack(spacing: 10) {
            if status.isFinished {
                Image(systemName: status.importedIDs.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.importedIDs.isEmpty ? .orange : .green)
                Text("\(status.importedIDs.count) Dateien importiert")
                Spacer(minLength: 4)
                if status.isQueued {
                    Text("In der Warteschlange")
                        .foregroundStyle(.secondary)
                } else if !status.importedIDs.isEmpty {
                    Button("Transkribieren") { appModel.transcribeImported() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
                Button("Schließen", systemImage: "xmark") { appModel.dismissImportStatus() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            } else {
                ProgressView(value: Double(status.completed), total: Double(status.total))
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Importiere \(status.completed + 1) von \(status.total) …")
                    .monospacedDigit()
                Spacer(minLength: 4)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Shown while files are dragged over the window.
struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 24, style: .continuous))
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 40))
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
