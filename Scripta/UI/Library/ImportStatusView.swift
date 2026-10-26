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
                    Button("Transkribieren", action: appModel.transcribeImported)
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
                Button("Schließen", systemImage: "xmark", action: appModel.dismissImportStatus)
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
