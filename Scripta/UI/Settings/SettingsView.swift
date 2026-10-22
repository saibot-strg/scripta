import AppKit
import AVFAudio
import ServiceManagement
import SwiftUI

/// Settings window. Recording settings since milestone 2; completed in milestone 6.
struct SettingsView: View {
    enum Pane: String, Hashable {
        case general, recording, transcription, people, dictation, permissions
    }

    @State private var pane: Pane

    init(pane: Pane = .general) {
        _pane = State(initialValue: pane)
    }

    var body: some View {
        TabView(selection: $pane) {
            Tab("Allgemein", systemImage: "gearshape", value: .general) {
                GeneralSettingsView()
            }
            Tab("Aufnahme", systemImage: "mic", value: .recording) {
                RecordingSettingsView()
            }
            Tab("Transkription", systemImage: "text.bubble", value: .transcription) {
                TranscriptionSettingsView()
            }
            Tab("Personen", systemImage: "person.2", value: .people) {
                PeopleSettingsView()
            }
            Tab("Diktat", systemImage: "mic.badge.plus", value: .dictation) {
                DictationSettingsView()
            }
            Tab("Berechtigungen", systemImage: "lock.shield", value: .permissions) {
                PermissionsSettingsView()
            }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.checksForUpdates) private var checksForUpdates = true
    /// Off by default: recording and transcribing are separate steps.
    @AppStorage(SettingsKey.autoTranscribe) private var autoTranscribe = false
    @AppStorage(SettingsKey.appearance) private var appearance: AppAppearance = .system
    @AppStorage(SettingsKey.showsMenuBarIcon) private var showsMenuBarIcon = true
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { appearance.apply() }
            }
            Section {
                Toggle("Automatisch transkribieren", isOn: $autoTranscribe)
            } footer: {
                Text("Neue Aufnahmen und Importe werden direkt in die Warteschlange gestellt.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Symbol in der Menüleiste", isOn: $showsMenuBarIcon)
                Toggle("Beim Anmelden starten", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchesAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            } footer: {
                Text("Praktisch für das Diktat: Das Tastenkürzel funktioniert, solange Scripta läuft.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Automatisch nach Updates suchen", isOn: $checksForUpdates)
                    .onChange(of: checksForUpdates) { _, enabled in
                        if enabled { Task { await appModel.updates.checkIfDue() } }
                    }
                LabeledContent("Version \(appModel.updates.currentVersion.description)") {
                    Button("Jetzt suchen") {
                        Task { await appModel.updates.checkNow() }
                    }
                    .disabled(appModel.updates.isChecking)
                }
            } footer: {
                Text("Scripta fragt einmal am Tag bei GitHub nach, ob es eine neue Version gibt. Daten über deine Aufnahmen oder deine Nutzung werden dabei nicht übertragen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 430)
    }
}

private struct RecordingSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.recordingFormat) private var format: RecordingFileFormat = .aac
    @AppStorage(SettingsKey.recordingQuality) private var quality: RecordingQuality = .standard
    @AppStorage(SettingsKey.meetingSource) private var meetingSource = ""
    @AppStorage(SettingsKey.levelsMicrophone) private var levelsMicrophone = true
    @State private var apps: [MeetingApp] = []

    var body: some View {
        let locations = appModel.library.locations
        Form {
            Section {
                MicrophonePicker()
                Toggle(isOn: $levelsMicrophone) {
                    Text("Leises Mikrofon anheben")
                    Text("Bringt deine Stimme nach der Aufnahme auf normale Lautstärke, etwa bei leisen Headsets.")
                }
            } footer: {
                Text("Gilt für Aufnahmen, Meetings („Ich“) und das Diktat.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Format", selection: $format) {
                    ForEach(RecordingFileFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("Qualität", selection: $quality) {
                    ForEach(RecordingQuality.allCases) { Text($0.label).tag($0) }
                }
                .disabled(format != .aac)
            } footer: {
                Text("Während der Aufnahme wird verlustfrei und absturzsicher gespeichert. Danach wird die Datei im gewählten Format abgelegt. Für die Transkription spielt das Format keine Rolle.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Standard-Quelle", selection: $meetingSource) {
                    Text("Gesamtes Systemaudio").tag("")
                    if !meetingSource.isEmpty, !apps.contains(where: { $0.bundleID == meetingSource }) {
                        // Keep the stored choice visible while that app isn't running.
                        Text(meetingSource).tag(meetingSource)
                    }
                    ForEach(apps) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
            } header: {
                Text("Meetings")
            } footer: {
                Text("Mikrofon („Ich“) und Systemaudio („Andere“) werden als getrennte Spuren aufgenommen. Mit Kopfhörern bleiben die Spuren am saubersten getrennt.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Neue Aufnahmen") {
                    Text(locations.current.rootURL.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Ändern …") { appModel.chooseStorageFolder() }
                    if !locations.isDefault {
                        Button("Standard verwenden") { appModel.useDefaultStorage() }
                    }
                    Spacer()
                    Button("Im Finder zeigen") {
                        let url = locations.current.rootURL
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .disabled(appModel.recorder.isActive)
            } header: {
                Text("Speicherort")
            } footer: {
                Text("Bestehende Aufnahmen bleiben, wo sie sind. Ordner in iCloud Drive oder auf externen Platten funktionieren, solange sie verfügbar sind.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .task {
            apps = AudioAppCatalog.availableApps()
            appModel.refreshMicrophones()
        }
    }
}

/// Voice recognition: opt-in, known people, deleting voice profiles.
private struct PeopleSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.recognizesVoices) private var recognizesVoices = false
    @State private var personToRename: PersonSummary?
    @State private var newName = ""
    @State private var personToDelete: PersonSummary?
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        let people = appModel.voices.people
        Form {
            Section {
                Toggle(isOn: $recognizesVoices) {
                    Text("Stimmen wiedererkennen")
                    Text("Scripta merkt sich die Stimmen der Personen, die du in Transkripten benennst, und erkennt sie in späteren Aufnahmen wieder.")
                }
            } footer: {
                Text("Stimmprofile sind biometrische Daten. Sie bleiben auf diesem Mac und lassen sich hier jederzeit löschen. Frag die Personen, ob das für sie in Ordnung ist.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if people.isEmpty {
                    Text("Noch niemand. Benenne Sprecher in einem Transkript, dann merkt sich Scripta ihre Stimmen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(people) { person in
                    LabeledContent {
                        Menu {
                            Button("Umbenennen …") {
                                newName = person.name
                                personToRename = person
                            }
                            Button("Löschen …", role: .destructive) { personToDelete = person }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    } label: {
                        Text(person.name)
                        Text(details(of: person))
                    }
                }
            } header: {
                Text("Personen")
            } footer: {
                Text("Ab \(VoiceMatcher.confirmedSamplesForAutomatic) bestätigten Stimmproben setzt Scripta den Namen selbst, vorher schlägt es ihn vor.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Alle Stimmprofile löschen …", role: .destructive) { isConfirmingDeleteAll = true }
                    .disabled(people.isEmpty && appModel.voices.statuses.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .alert("Person umbenennen", isPresented: Binding(
            get: { personToRename != nil },
            set: { if !$0 { personToRename = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Umbenennen") {
                if let personToRename { appModel.renamePerson(personToRename.id, to: newName) }
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Name ändert sich auch in allen Transkripten, in denen die Person erkannt oder benannt wurde.")
        }
        .confirmationDialog(
            "„\(personToDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { personToDelete != nil }, set: { if !$0 { personToDelete = nil } })
        ) {
            Button("Löschen", role: .destructive) {
                if let personToDelete { appModel.deletePerson(personToDelete.id) }
            }
        } message: {
            Text("Die Stimmproben werden gelöscht. Namen in Transkripten bleiben stehen.")
        }
        .confirmationDialog("Alle Stimmprofile löschen?", isPresented: $isConfirmingDeleteAll) {
            Button("Alle löschen", role: .destructive) { appModel.deleteAllVoiceProfiles() }
        } message: {
            Text("Alle Personen, Stimmproben und Stimm-Fingerabdrücke werden gelöscht. Namen in Transkripten bleiben stehen.")
        }
    }

    private func details(of person: PersonSummary) -> String {
        let confirmed = String(localized: "Bestätigte Stimmproben: \(person.confirmedSamples)")
        let mode = person.confirmedSamples >= VoiceMatcher.confirmedSamplesForAutomatic
            ? String(localized: "wird automatisch erkannt")
            : String(localized: "wird vorgeschlagen")
        return "\(confirmed) · \(mode)"
    }
}

private struct TranscriptionSettingsView: View {
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
        .scrollDisabled(true)
        .frame(height: 750)
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

private extension URL {
    /// Total size of all files below this directory.
    var directorySize: Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}

private struct PermissionsSettingsView: View {
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var canPaste = TextInserter.canPostEvents

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    switch microphone {
                    case .granted:
                        Label("Erlaubt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .undetermined:
                        Button("Zugriff erlauben") {
                            Task {
                                _ = await AVAudioApplication.requestRecordPermission()
                                microphone = AVAudioApplication.shared.recordPermission
                            }
                        }
                    default:
                        openButton(.microphone)
                    }
                } label: {
                    Label("Mikrofon", systemImage: "mic")
                    Text("Für Aufnahmen und Meetings („Ich“).")
                }

                LabeledContent {
                    openButton(.systemAudio)
                } label: {
                    Label("Systemaudio", systemImage: "speaker.wave.2")
                    Text("Für Meetings („Andere“). macOS fragt beim ersten Meeting nach; der Status lässt sich nicht automatisch prüfen.")
                }

                LabeledContent {
                    if canPaste {
                        Label("Erlaubt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        openButton(.accessibility)
                    }
                } label: {
                    Label("Bedienungshilfen", systemImage: "keyboard")
                    Text("Für das Diktat: Text per ⌘V in andere Apps einfügen.")
                }
            } footer: {
                Text("Scripta arbeitet komplett lokal. Audio und Transkripte verlassen deinen Mac nicht.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 320)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphone = AVAudioApplication.shared.recordPermission
            canPaste = TextInserter.canPostEvents
        }
    }

    private func openButton(_ pane: PrivacyPane) -> some View {
        Button("Systemeinstellungen öffnen") {
            if let url = pane.url { NSWorkspace.shared.open(url) }
        }
    }
}

private struct PlaceholderSettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Folgt in einem späteren Meilenstein",
            systemImage: "hammer"
        )
        .frame(height: 160)
    }
}
