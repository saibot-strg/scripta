import SwiftUI

/// Settings › Transkription: speech model and speaker separation.
struct TranscriptionSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.separatesSpeakers) private var separatesSpeakers = true
    @AppStorage(SettingsKey.separatesRoomSpeakers) private var separatesRoomSpeakers = false
    @State private var modelSize: Int64?
    @State private var diarizerSize: Int64?
    @State private var isConfirmingDelete = false

    var body: some View {
        let service = appModel.transcription
        Form {
            Section {
                LabeledContent("Sprache") {
                    Text("Automatisch")
                }
            } footer: {
                Text("Parakeet erkennt Deutsch, Englisch und 23 weitere europäische Sprachen selbst. Eine feste Sprachwahl ist bei diesem Modell nicht möglich.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Modell") {
                    Text(verbatim: "Parakeet Ultra")
                }
                LabeledContent("Status") {
                    modelStatus(service.modelState)
                }
                if let modelSize {
                    LabeledContent("Speicherbedarf") {
                        Text(modelSize, format: .byteCount(style: .file))
                    }
                }
                HStack {
                    if service.isModelInstalled {
                        Button("Neu laden") {
                            Task {
                                await service.deleteModel()
                                try? await service.prepareModel()
                                updateSize()
                            }
                        }
                        Button("Löschen …", role: .destructive) { isConfirmingDelete = true }
                    } else {
                        Button("Jetzt laden") {
                            Task {
                                try? await service.prepareModel()
                                updateSize()
                            }
                        }
                    }
                }
                .disabled(service.isBusy)
            } header: {
                Text("Spracherkennung")
            } footer: {
                Text("Läuft auf der Neural Engine dieses Macs. Das Modell wird einmalig von Hugging Face geladen; danach arbeitet Scripta komplett offline. Modell: Parakeet Ultra von moondream auf Basis von NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0), CoreML-Fassung von FluidInference.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Sprecher unterscheiden", isOn: $separatesSpeakers)
                if separatesSpeakers {
                    Toggle(isOn: $separatesRoomSpeakers) {
                        Text("Mehrere Personen am Mikrofon")
                        Text("Für Meetings, in denen weitere Personen mit dir am Mac sitzen. Ist im Meeting niemand online zu hören, geschieht das automatisch.")
                    }
                    LabeledContent("Status") {
                        modelStatus(service.diarizerState)
                    }
                    if let diarizerSize {
                        LabeledContent("Speicherbedarf") {
                            Text(diarizerSize, format: .byteCount(style: .file))
                        }
                    }
                    HStack {
                        if service.isDiarizerInstalled {
                            Button("Löschen", role: .destructive) {
                                Task {
                                    await service.deleteDiarizer()
                                    updateSize()
                                }
                            }
                        } else {
                            Button("Jetzt laden") {
                                Task {
                                    try? await service.prepareDiarizer()
                                    updateSize()
                                }
                            }
                        }
                    }
                    .disabled(service.isBusy)
                }
            } header: {
                Text("Sprecher")
            } footer: {
                Text("Trennt die Stimmen in Meetings und Aufnahmen („Sprecher 1“, „Sprecher 2“ …); deine eigene Stimme im Meeting bleibt „Ich“. Modell: pyannote community-1 mit WeSpeaker (CC BY 4.0), CoreML-Fassung von FluidInference. Läuft ebenfalls lokal.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 640)
        .task { updateSize() }
        .confirmationDialog("Modell löschen?", isPresented: $isConfirmingDelete) {
            Button("Löschen", role: .destructive) {
                Task {
                    await service.deleteModel()
                    updateSize()
                }
            }
        } message: {
            Text("Für die nächste Transkription wird es erneut geladen (ca. 640 MB).")
        }
    }

    @ViewBuilder
    private func modelStatus(_ state: TranscriptionService.ModelState) -> some View {
        switch state {
        case .notInstalled:
            Text("Nicht geladen")
        case .installed, .ready:
            Label("Installiert", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading(let fraction):
            HStack {
                ProgressView(value: fraction).frame(width: 120)
                Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Wird vorbereitet …")
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func updateSize() {
        let service = appModel.transcription
        modelSize = service.isModelInstalled ? ParakeetEngine.modelDirectory.directorySize : nil
        diarizerSize = service.isDiarizerInstalled ? SpeakerDiarizer.modelDirectory.directorySize : nil
    }
}
