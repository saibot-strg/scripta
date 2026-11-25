import SwiftUI
import UniformTypeIdentifiers

/// Settings › Erkennung, last part: models for titles and summaries and their
/// downloads, as sections for the pane's form.
struct LanguageModelSettingsSections: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.suggestsTitles) private var suggestsTitles = true
    @State private var isImportingFile = false
    @State private var deleteTarget: LanguageModelDescriptor?

    var body: some View {
        let service = appModel.languageModels
        let usable = service.allModels.filter(service.isUsable)

        Section {
            Toggle(isOn: $suggestsTitles) {
                Text("Titel automatisch vorschlagen")
                Text("Nach der ersten Transkription ersetzt Scripta „Aufnahme …“ oder „Meeting …“ durch einen Titel aus dem Inhalt. Titel, die du selbst vergibst, bleiben. Mit ⌘Z kehrst du zum alten Titel zurück.")
            }
            Picker("Modell", selection: Binding(
                get: { service.titleModel?.id ?? "" },
                set: { service.titleModelID = $0 }
            )) {
                if usable.isEmpty {
                    Text("Kein Modell verfügbar").tag("")
                }
                ForEach(usable) { model in
                    Text(verbatim: model.name).tag(model.id)
                }
            }
        } header: {
            Text("Titel")
        } footer: {
            Text("Apple Intelligence sieht bei langen Aufnahmen Ausschnitte aus Anfang, Mitte und Ende. Ein geladenes Modell liest das ganze Transkript.")
                .foregroundStyle(.secondary)
        }

        Section {
            let summarizers = usable.filter(\.canSummarize)
            Picker("Modell", selection: Binding(
                get: { service.summaryModel?.id ?? "" },
                set: { service.summaryModelID = $0 }
            )) {
                if summarizers.isEmpty {
                    Text("Kein Modell geladen").tag("")
                }
                ForEach(summarizers) { model in
                    Text(verbatim: model.name).tag(model.id)
                }
            }
            .disabled(summarizers.isEmpty)
        } header: {
            Text("Zusammenfassung")
        } footer: {
            Text("Für Zusammenfassungen brauchst du eines der Modelle unten. Apple Intelligence sieht zu wenig vom Transkript auf einmal.")
                .foregroundStyle(.secondary)
        }

        Section {
            ForEach(service.allModels) { model in
                LanguageModelRow(model: model) { deleteTarget = model }
            }
            Button("Eigene GGUF-Datei hinzufügen …") { isImportingFile = true }
                .onAppear { service.refreshInstallStates() }
                .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
                    guard case .success(let url) = result else { return }
                    appModel.perform { try service.addCustomModel(at: url) }
                }
                .confirmationDialog(
                    "Modell löschen?",
                    isPresented: $deleteTarget.isPresent,
                    presenting: deleteTarget
                ) { model in
                    Button("Löschen", role: .destructive) {
                        Task { await service.delete(model) }
                    }
                } message: { model in
                    if model.isCustom {
                        Text("Die Datei bleibt, wo sie ist; Scripta vergisst sie nur.")
                    } else {
                        Text("\(model.name) wird vom Mac gelöscht. Du kannst es jederzeit wieder laden.")
                    }
                }
        } header: {
            Text("Modelle")
        } footer: {
            Text("Alle Modelle laufen auf diesem Mac; Transkripte verlassen ihn nicht. Modelle werden einmalig von Hugging Face geladen (Apache 2.0). Empfohlen: Qwen 3.5 4B. Beim Schreiben braucht ein Modell etwa so viel Arbeitsspeicher wie sein Download groß ist, plus bis zu 1 GB.")
                .foregroundStyle(.secondary)
        }
    }
}

/// One model: name, size and its download state with the matching action.
private struct LanguageModelRow: View {
    @Environment(AppModel.self) private var appModel
    let model: LanguageModelDescriptor
    let onDelete: () -> Void

    var body: some View {
        let service = appModel.languageModels
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: model.name)
                    if model.isRecommended {
                        Text("Empfohlen")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if model.runtime == .apple {
                appleStatus
            } else {
                status(service.installStates[model.id] ?? .notInstalled)
            }
        }
    }

    private var details: String {
        guard model.downloadSize > 0 else { return model.runtimeLabel }
        return "\(model.runtimeLabel) · \(model.downloadSize.formatted(.byteCount(style: .file)))"
    }

    @ViewBuilder
    private var appleStatus: some View {
        if let reason = AppleIntelligenceEngine.unavailableReason {
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 220, alignment: .trailing)
        } else {
            Label("Bereit", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.success)
        }
    }

    @ViewBuilder
    private func status(_ state: LanguageModelService.InstallState) -> some View {
        let service = appModel.languageModels
        switch state {
        case .notInstalled where model.isCustom:
            HStack(spacing: 8) {
                Text("Datei nicht gefunden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Entfernen …", role: .destructive, action: onDelete)
            }
        case .notInstalled:
            Button("Laden") { service.download(model) }
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 90)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .font(.caption)
                Button("Abbrechen", systemImage: "xmark.circle.fill") { service.cancelDownload(model) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Download abbrechen")
            }
        case .installed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.success)
                    .accessibilityLabel(Text("Installiert"))
                Button(model.isCustom ? LocalizedStringKey("Entfernen …") : "Löschen …", role: .destructive, action: onDelete)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
                    .accessibilityLabel(Text(message))
                Button("Erneut versuchen") { service.download(model) }
            }
        }
    }
}
