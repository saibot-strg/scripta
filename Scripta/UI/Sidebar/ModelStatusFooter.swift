import SwiftUI

/// Sidebar footer while the speech model downloads, loads or failed.
struct ModelStatusFooter: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let state = appModel.transcription.modelState
        Group {
            switch state {
            case .downloading(let fraction):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Spracherkennung wird geladen", systemImage: "arrow.down.circle")
                        .font(.caption.weight(.semibold))
                    ProgressView(value: fraction)
                        .controlSize(.small)
                    Text("Einmalig ca. 640 MB, danach komplett offline.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .loading:
                Label {
                    Text("Modell wird vorbereitet …")
                } icon: {
                    ProgressView().controlSize(.mini)
                }
                .font(.caption.weight(.semibold))
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Modell nicht verfügbar", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Button("Erneut versuchen") {
                        Task { try? await appModel.transcription.prepareModel() }
                    }
                    .controlSize(.small)
                }
            case .notInstalled, .installed, .ready:
                EmptyView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
