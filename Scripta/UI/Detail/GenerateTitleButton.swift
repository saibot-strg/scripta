import SwiftUI

/// "Titel erzeugen" in the detail toolbar; a spinner while the model writes.
struct GenerateTitleButton: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    var body: some View {
        let service = appModel.languageModels
        if service.titleJobs.contains(recording.id) {
            ProgressView()
                .controlSize(.small)
                .help("Titel wird erzeugt …")
        } else {
            Button("Titel erzeugen", systemImage: "wand.and.sparkles") {
                appModel.generateTitle(for: recording)
            }
            .disabled(!appModel.canGenerateTitle(for: recording))
            .help(help(model: service.titleModel))
        }
    }

    private func help(model: LanguageModelDescriptor?) -> String {
        if recording.transcript?.segments.isEmpty ?? true {
            return String(localized: "Titel erzeugen: zuerst transkribieren")
        }
        guard let model else {
            return String(localized: "Titel erzeugen: schalte Apple Intelligence ein oder lade ein Sprachmodell (Einstellungen › Erkennung)")
        }
        return String(localized: "Titel aus dem Transkript erzeugen (\(model.name))")
    }
}
