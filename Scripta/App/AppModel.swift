import AppKit
import Foundation
import SwiftData
import SwiftUI
import os

/// App-wide UI state and entry point to the services. One instance per app,
/// owned by `ScriptaApp` and shared through the SwiftUI environment.
@MainActor
@Observable
final class AppModel {
    let library: LibraryService
    let recorder: AudioRecorder
    let transcription: TranscriptionService
    /// Known people and their voices (separate store, opt-in).
    let voices: VoiceLibrary
    let dictation: DictationController
    let player = PlayerModel()
    let updates = UpdateChecker()

    var sidebarSelection: SidebarItem? = .all
    /// Selection by the recording's own UUID. SwiftData's `persistentModelID`
    /// changes when a new object is saved, so it can't identify fresh recordings.
    var selectedRecordingID: UUID? {
        didSet {
            if oldValue != selectedRecordingID { player.unload() }
        }
    }
    var searchText = ""
    /// Incremented to move keyboard focus into the search field (⌘F).
    private(set) var searchFocusRequest = 0

    /// Error or notice shown in the main window's alert.
    var presentedError: PresentableError?

    /// Recordings currently being encoded to AAC.
    private(set) var encodingIDs: Set<UUID> = []

    /// Without `voices`, an empty in-memory voice store is used (tests, previews).
    init(library: LibraryService, voices: VoiceLibrary? = nil) {
        self.library = library
        let voices = voices ?? .makeInMemory()
        self.voices = voices
        recorder = AudioRecorder(location: { [library] in
            RecordingLocation(storage: library.storage, bookmark: library.locations.currentBookmark)
        })
        transcription = TranscriptionService(library: library, diarizer: SpeakerDiarizer(), voices: voices)
        dictation = DictationController(transcription: transcription)
        recorder.onFailure = { [weak self] error in
            self?.stopRecording()
            self?.presentedError = PresentableError(error)
        }
        // Keep the meeting source menu current as apps launch and quit.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMeetingApps() }
            }
        }
        // Keep the microphone menus current as headsets come and go.
        refreshMicrophones()
        deviceObservation = AudioDeviceObservation { [weak self] in self?.refreshMicrophones() }
    }

    /// The selected recording, if it still exists.
    var selectedRecording: Recording? {
        selectedRecordingID.flatMap(library.recording(withID:))
    }

    // MARK: - Startup

    /// Recovers interrupted recordings and finishes pending AAC encodings.
    func performStartupMaintenance() async {
        let recovered = await RecordingRecovery(library: library)
            .recoverInterruptedRecordings(activeRecordingID: { [recorder] in recorder.activeRecordingID })
        if recovered > 0 {
            presentedError = PresentableError(
                title: String(localized: "Aufnahme wiederhergestellt"),
                message: String(localized: "Scripta wurde während einer Aufnahme beendet. Alles bis zu diesem Zeitpunkt ist gespeichert.")
            )
        }
        let recordings = (try? library.modelContext.fetch(FetchDescriptor<Recording>())) ?? []
        for recording in recordings {
            encodeIfNeeded(recording)
        }
        transcription.resumePendingJobs()
        dictation.applySettings()
        updates.startAutomaticChecks()
        await transcription.installModelIfNeeded()
    }

    // MARK: - Import

    /// Progress and result of the latest import, shown above the list.
    struct ImportStatus: Equatable {
        let id = UUID()
        var total: Int
        var completed = 0
        var importedIDs: [UUID] = []
        var isFinished = false
        var isQueued = false
    }

    var isImporterPresented = false
    private(set) var importStatus: ImportStatus?

    /// Imports files one after another; the file work runs off the main actor.
    /// `folder`: files dropped onto a folder in the sidebar land there.
    func importFiles(_ urls: [URL], into folder: Folder? = nil) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        Task { await performImport(files, folderID: folder?.id) }
    }

    private func performImport(_ urls: [URL], folderID: UUID? = nil) async {
        let autoTranscribe = UserDefaults.standard.bool(forKey: SettingsKey.autoTranscribe)
        var status = ImportStatus(total: urls.count, isQueued: autoTranscribe)
        importStatus = status
        var failures: [String] = []
        let storage = library.storage
        let bookmark = library.locations.currentBookmark

        for url in urls {
            do {
                let prepared = try await AudioImporter.prepare(url, storage: storage)
                let recording = try library.addRecording(
                    manifest: prepared.manifest, duration: prepared.duration, rootBookmark: bookmark
                )
                if let folder = folderID.flatMap(library.folder(withID:)) {
                    try library.move([recording], to: folder)
                }
                status.importedIDs.append(recording.id)
                if autoTranscribe { transcription.enqueue(recording) }
            } catch {
                failures.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            status.completed += 1
            importStatus = status
        }

        status.isFinished = true
        importStatus = status
        if let last = status.importedIDs.last.flatMap(library.recording(withID:)) {
            reveal(last)
        }
        if !failures.isEmpty {
            presentedError = PresentableError(
                title: String(localized: "Nicht alle Dateien konnten importiert werden"),
                message: failures.joined(separator: "\n")
            )
        }
        // Leave the summary visible for a moment.
        try? await Task.sleep(for: .seconds(10))
        if importStatus?.id == status.id { importStatus = nil }
    }

    /// "Transkribieren" in the import summary.
    func transcribeImported() {
        guard let status = importStatus else { return }
        for recording in status.importedIDs.compactMap(library.recording(withID:)) where recording.status != .done {
            transcription.enqueue(recording)
        }
        importStatus?.isQueued = true
    }

    func dismissImportStatus() {
        importStatus = nil
    }

    // MARK: - Transcript editing

    /// Saves a manual correction; the engine's text is kept for "restore".
    func edit(_ segment: TranscriptSegment, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != segment.text else { return }
        segment.applyEdit(trimmed)
        segment.transcript?.rebuildFullText()
        perform { try library.save() }
    }

    func restoreOriginalText(of segment: TranscriptSegment) {
        guard let original = segment.originalText else { return }
        segment.text = original
        segment.originalText = nil
        segment.transcript?.rebuildFullText()
        perform { try library.save() }
    }

    /// An empty name restores the default ("Ich", "Andere", "Sprecher 2").
    /// The name of another speaker in the same transcript merges both: the
    /// diarization split one person into several voices. With voice
    /// recognition on, a name also teaches Scripta that person's voice,
    /// unless `remember` is off (a guest).
    func rename(_ speaker: SpeakerLabel, to name: String, remember: Bool = true) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let transcript = speaker.transcript else { return }
        if !trimmed.isEmpty, let existing = transcript.speakers.first(where: {
            $0.id != speaker.id && $0.displayName.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            merge(speaker, into: existing)
            return
        }
        setName(trimmed, of: speaker, remember: remember)
        transcript.rebuildFullText()
        perform { try library.save() }
    }

    /// One name given in the assignment sheet.
    struct NameAssignment {
        var speaker: SpeakerLabel
        var name: String
        var remember: Bool
    }

    /// Applies the names of the assignment sheet together. Speakers that end
    /// up with the same name are merged; a name that only matches another
    /// speaker's *old* name is not (e.g. two guessed names swapped).
    func assignNames(_ assignments: [NameAssignment], in transcript: Transcript) {
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var finalNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, key($0.displayName)) })
        for assignment in assignments {
            let name = key(assignment.name)
            finalNames[assignment.speaker.id] = name.isEmpty ? key(assignment.speaker.defaultName) : name
        }
        // Speakers named in the sheet first, so they keep their passages' label.
        let named = assignments.map(\.speaker)
        let ordered = named + transcript.speakers.filter { speaker in !named.contains { $0.id == speaker.id } }
        var survivors: [String: SpeakerLabel] = [:]
        var merged: Set<UUID> = []
        for speaker in ordered {
            guard let name = finalNames[speaker.id] else { continue }
            if let target = survivors[name] {
                merge(speaker, into: target)
                merged.insert(speaker.id)
            } else {
                survivors[name] = speaker
            }
        }
        for assignment in assignments where !merged.contains(assignment.speaker.id) {
            setName(assignment.name.trimmingCharacters(in: .whitespacesAndNewlines), of: assignment.speaker, remember: assignment.remember)
        }
        transcript.rebuildFullText()
        perform { try library.save() }
    }

    /// Sets the name without looking at other speakers. An empty or default
    /// name restores the default and forgets the voice link.
    private func setName(_ name: String, of speaker: SpeakerLabel, remember: Bool) {
        let isDefault = name.isEmpty || name == speaker.defaultName
        speaker.customName = isDefault ? nil : name
        if isDefault || !remember {
            voices.unlink(labelID: speaker.id)
        } else {
            voices.link(labelID: speaker.id, toPersonNamed: name)
        }
    }

    /// Takes the suggested person ("Max?") as the speaker's name.
    func confirmSuggestion(for speaker: SpeakerLabel) {
        guard let name = voices.statuses[speaker.id]?.personName else { return }
        rename(speaker, to: name)
    }

    /// Moves all of `speaker`'s segments to `target` (same transcript) and
    /// removes `speaker`: one person the diarization split into several voices.
    func merge(_ speaker: SpeakerLabel, into target: SpeakerLabel) {
        guard let transcript = speaker.transcript, target.transcript?.id == transcript.id, target.id != speaker.id else { return }
        voices.merge(labelID: speaker.id, into: target.id)
        for segment in Array(speaker.segments) {
            segment.speaker = target
        }
        transcript.speakers.removeAll { $0.id == speaker.id }
        library.modelContext.delete(speaker)
        transcript.rebuildFullText()
        perform { try library.save() }
    }

    // MARK: - Export

    /// Short confirmation at the bottom of the window ("Transkript kopiert").
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    func exportDocument(for recording: Recording) -> TranscriptDocument? {
        guard let transcript = recording.transcript, !transcript.segments.isEmpty else { return nil }
        return TranscriptDocument(recording: recording, transcript: transcript)
    }

    /// Asks where to save, then writes the transcript in the chosen format.
    func export(_ recording: Recording, as format: ExportFormat) {
        guard let document = exportDocument(for: recording) else { return }
        Task {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [format.contentType]
            panel.nameFieldStringValue = Self.fileName(for: recording.title) + "." + format.fileExtension
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            let response = if let window = NSApp.keyWindow {
                await panel.beginSheetModal(for: window)
            } else {
                panel.runModal()
            }
            guard response == .OK, let url = panel.url else { return }
            do {
                try TranscriptExporter.data(document, as: format).write(to: url, options: .atomic)
                showToast(String(localized: "Exportiert"))
            } catch {
                presentedError = PresentableError(error)
            }
        }
    }

    func copyTranscript(of recording: Recording) {
        guard let document = exportDocument(for: recording) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptExporter.plainText(document, includeHeader: false), forType: .string)
        showToast(String(localized: "Transkript kopiert"))
    }

    /// Text for the share menu (Mail, Nachrichten, Notizen …).
    func shareText(for recording: Recording) -> String? {
        exportDocument(for: recording).map { TranscriptExporter.plainText($0, includeHeader: true) }
    }

    /// A title that is safe as a file name.
    nonisolated static func fileName(for title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "Transkript") : cleaned
    }

    // MARK: - Transcription

    /// `speakerCount` corrects a wrong separation: the voices on the system
    /// track (meetings) or in the recording.
    func transcribe(_ recording: Recording, speakerCount: Int? = nil) {
        transcription.enqueue(recording, speakerCount: speakerCount)
    }

    /// Queues every recording without a transcript (batch transcription).
    func transcribeAllPending() {
        let all = (try? library.modelContext.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for recording in all where (recording.status == .notTranscribed || recording.status == .failed)
            && library.audioURL(for: recording) != nil {
            transcription.enqueue(recording)
        }
    }

    var pendingTranscriptionCount: Int {
        let all = (try? library.modelContext.fetch(FetchDescriptor<Recording>())) ?? []
        return all.count { ($0.status == .notTranscribed || $0.status == .failed) && library.audioURL(for: $0) != nil }
    }

    func cancelTranscription(of recording: Recording) {
        transcription.cancel(recording)
    }

    // MARK: - Recording

    /// Stopped recordings whose files are still being finished (levelling,
    /// mixing), by kind for the status text.
    private(set) var savingSources: [RecordingSource] = []
    var isSavingRecording: Bool { !savingSources.isEmpty }
    /// Apps that can be recorded on their own in a meeting.
    private(set) var meetingApps: [MeetingApp] = []
    /// Inputs for the microphone menus, kept current as devices come and go.
    private(set) var microphones: [AudioInputDevice] = []
    /// The system's default input ("Systemstandard").
    private(set) var defaultMicrophone: AudioInputDevice?
    @ObservationIgnored private var deviceObservation: AudioDeviceObservation?

    func toggleRecording() {
        if recorder.isActive {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        guard !recorder.isActive else { return }
        do {
            try ensureFreeSpace()
            try await ensureMicrophoneAccess()
            let title = String(localized: "Aufnahme \(Date.now.formatted(date: .abbreviated, time: .shortened))")
            try await recorder.startMicrophone(title: title)
        } catch {
            presentedError = PresentableError(error)
        }
    }

    /// Records microphone and system audio as separate tracks.
    /// - Parameter target: nil uses the default source from the settings.
    func startMeeting(_ target: SystemAudioTarget? = nil) async {
        guard !recorder.isActive else { return }
        do {
            try ensureFreeSpace()
            try await ensureMicrophoneAccess()
            let target = target ?? defaultMeetingTarget()
            let date = Date.now.formatted(date: .abbreviated, time: .shortened)
            let title = switch target {
            case .allSystemAudio: String(localized: "Meeting \(date)")
            case .application(let app): String(localized: "Meeting \(app.name) \(date)")
            }
            try await recorder.startMeeting(title: title, target: target)
        } catch {
            presentedError = PresentableError(error)
        }
    }

    func refreshMeetingApps() {
        let apps = AudioAppCatalog.availableApps()
        // Assign only on change: every assignment re-renders the menus.
        if apps != meetingApps { meetingApps = apps }
    }

    func refreshMicrophones() {
        // Assign only on change: every assignment re-renders the menus.
        let inputs = AudioInputDevices.available()
        if inputs != microphones { microphones = inputs }
        let defaultInput = AudioInputDevices.defaultDevice()
        if defaultInput != defaultMicrophone { defaultMicrophone = defaultInput }
    }

    /// Name of the microphone used for `uid` ("" = system default): the
    /// chosen one if connected, otherwise the system default.
    func microphoneName(forUID uid: String) -> String? {
        microphones.first { $0.uid == uid }?.name ?? defaultMicrophone?.name
    }

    /// Chooses the microphone for recordings, meetings and dictation ("" =
    /// system default). A running recording switches over right away.
    func selectMicrophone(_ uid: String) {
        guard uid != (RecordingSettings.microphoneUID ?? "") else { return }
        UserDefaults.standard.set(uid, forKey: SettingsKey.microphone)
        guard recorder.state == .recording || recorder.state == .paused else { return }
        do {
            try recorder.switchMicrophone()
        } catch {
            presentedError = PresentableError(error)
        }
    }

    private func defaultMeetingTarget() -> SystemAudioTarget {
        guard let bundleID = RecordingSettings.meetingSourceBundleID,
              let app = AudioAppCatalog.app(withBundleID: bundleID) else { return .allSystemAudio }
        return .application(app)
    }

    /// About an hour of a meeting in lossless PCM, before encoding.
    static let minimumFreeSpace: Int64 = 500_000_000

    private func ensureFreeSpace() throws(RecordingError) {
        if let available = library.storage.availableCapacity, available < Self.minimumFreeSpace {
            throw .notEnoughSpace
        }
    }

    private func ensureMicrophoneAccess() async throws(RecordingError) {
        #if DEBUG
        if recorder.usesTestTone { return }
        #endif
        try await MicrophonePermission.ensureAccess()
    }

    func togglePause() {
        switch recorder.state {
        case .recording:
            recorder.pause()
        case .paused:
            Task {
                do {
                    try await recorder.resume()
                } catch {
                    presentedError = PresentableError(error)
                }
            }
        case .idle, .starting:
            break
        }
    }

    /// Stops recording and adds the recording to the library once its files
    /// are finished in the background (microphone levelled, meeting mixed).
    @discardableResult
    func stopRecording() -> Task<Void, Never>? {
        guard let finished = recorder.stop() else { return nil }
        let source = finished.manifest.source
        savingSources.append(source)
        return Task {
            defer {
                if let index = savingSources.firstIndex(of: source) { savingSources.remove(at: index) }
            }
            do {
                let duration = try await RecordingFinisher.finish(finished.manifest, storage: finished.storage)
                addToLibrary(finished.manifest, duration: duration > 0 ? duration : finished.duration, rootBookmark: finished.rootBookmark)
            } catch {
                // The manifest stays on disk, so the recording is recovered on next launch.
                Logger.recording.error("Finishing failed: \(error.localizedDescription, privacy: .public)")
                presentedError = PresentableError(error)
            }
        }
    }

    /// Called when the app quits: closes the files. Microphone recordings are
    /// saved right away; meetings are mixed and saved on the next launch.
    func stopRecordingForTermination() {
        guard let finished = recorder.stop(), !finished.manifest.isMeeting else { return }
        _ = try? library.addRecording(manifest: finished.manifest, duration: finished.duration, rootBookmark: finished.rootBookmark)
    }

    private func addToLibrary(_ manifest: RecordingManifest, duration: TimeInterval, rootBookmark: Data?) {
        do {
            let recording = try library.addRecording(manifest: manifest, duration: duration, rootBookmark: rootBookmark)
            reveal(recording)
            encodeIfNeeded(recording)
            if UserDefaults.standard.bool(forKey: SettingsKey.autoTranscribe) {
                transcription.enqueue(recording)
            }
        } catch {
            // The manifest stays on disk, so the recording is recovered on next launch.
            presentedError = PresentableError(error)
        }
    }

    /// Encodes the PCM tracks of a recording to AAC in the background when AAC
    /// is selected. Until then (or if encoding fails) the PCM files stay usable.
    func encodeIfNeeded(_ recording: Recording) {
        guard RecordingSettings.fileFormat == .aac, !encodingIDs.contains(recording.id) else { return }
        let pending = recording.tracks
            .filter { $0.fileName.hasSuffix(".caf") }
            .map { (trackID: $0.id, fileName: $0.fileName) }
        guard !pending.isEmpty else { return }

        let id = recording.id
        let storage = library.storage(for: recording)
        let bitRate = RecordingSettings.quality.aacBitRate
        encodingIDs.insert(id)

        Task {
            defer { encodingIDs.remove(id) }
            for item in pending {
                let source = storage.fileURL(for: id, fileName: item.fileName)
                let encodedName = CaptureFormat.encodedFileName(for: item.fileName)
                let destination = storage.fileURL(for: id, fileName: encodedName)
                do {
                    try await AudioEncoder.encodeAAC(source: source, destination: destination, bitRate: bitRate)
                    // The recording may have been deleted in the meantime.
                    guard let recording = library.recording(withID: id),
                          let track = recording.tracks.first(where: { $0.id == item.trackID }) else {
                        try? FileManager.default.removeItem(at: destination)
                        return
                    }
                    try library.replaceFile(of: track, in: recording, with: encodedName)
                    if track.role == .primary, selectedRecordingID == id, !player.isPlaying {
                        player.load(destination)
                    }
                } catch {
                    Logger.recording.error("AAC encoding failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Playback

    func loadPlayer(for recording: Recording) {
        player.load(library.audioURL(for: recording))
    }

    /// Selects a recording and starts playback.
    func play(_ recording: Recording) {
        reveal(recording)
        loadPlayer(for: recording)
        player.play()
    }

    // MARK: - Library actions

    /// Runs a throwing action and shows its error in an alert.
    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            presentedError = PresentableError(error)
        }
    }

    func rename(_ recording: Recording, to title: String) {
        perform { try library.rename(recording, to: title) }
    }

    func delete(_ recording: Recording) {
        if selectedRecordingID == recording.id {
            selectedRecordingID = nil
        }
        transcription.cancel(recording)
        voices.forgetRecording(recording.id)
        perform { try library.delete(recording) }
    }

    /// Moves one passage to another speaker of the same transcript: the
    /// diarization put two people into one voice. The source speaker's voice
    /// is then a mix and no longer teaches anyone's profile. A speaker left
    /// without passages is removed.
    func move(_ segment: TranscriptSegment, to target: SpeakerLabel) {
        guard let source = segment.speaker, source.id != target.id,
              let transcript = segment.transcript, target.transcript?.id == transcript.id else { return }
        let sourceKeepsPassages = source.segments.contains { $0.id != segment.id }
        voices.discardVoice(labelID: source.id)
        segment.speaker = target
        if !sourceKeepsPassages {
            transcript.speakers.removeAll { $0.id == source.id }
            library.modelContext.delete(source)
        }
        transcript.rebuildFullText()
        perform { try library.save() }
    }

    /// Moves one passage to a new numbered speaker ("Sprecher 4"), named
    /// `name` if given (a known person not yet in this transcript). If a
    /// speaker already has that name, the passage goes there.
    func moveToNewSpeaker(_ segment: TranscriptSegment, named name: String? = nil) {
        guard let transcript = segment.transcript else { return }
        if let name, let existing = transcript.speakers.first(where: { $0.displayName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            move(segment, to: existing)
            return
        }
        let number = (transcript.speakers.filter { $0.role == .diarized }.map(\.number).max() ?? 0) + 1
        let label = SpeakerLabel(role: .diarized, number: number, customName: name)
        transcript.speakers.append(label)
        move(segment, to: label)
    }

    // MARK: - Folders

    func createFolder(named name: String) {
        perform {
            let folder = try library.createFolder(named: name)
            sidebarSelection = .folder(folder.id)
        }
    }

    func rename(_ folder: Folder, to name: String) {
        perform { try library.rename(folder, to: name) }
    }

    func delete(_ folder: Folder) {
        if sidebarSelection == .folder(folder.id) { sidebarSelection = .all }
        perform { try library.delete(folder) }
    }

    /// Files recordings by ID (drag and drop) in a folder, nil = out of any folder.
    func move(recordingIDs: [UUID], to folder: Folder?) {
        let recordings = recordingIDs.compactMap(library.recording(withID:))
        guard !recordings.isEmpty else { return }
        perform { try library.move(recordings, to: folder) }
    }

    // MARK: - People

    /// Renames a known person and every speaker named after them.
    func renamePerson(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var transcripts: [UUID: Transcript] = [:]
        for labelID in voices.rename(personID: id, to: trimmed) {
            let descriptor = FetchDescriptor<SpeakerLabel>(predicate: #Predicate { $0.id == labelID })
            guard let label = try? library.modelContext.fetch(descriptor).first else { continue }
            label.customName = trimmed
            if let transcript = label.transcript { transcripts[transcript.id] = transcript }
        }
        for transcript in transcripts.values { transcript.rebuildFullText() }
        perform { try library.save() }
    }

    func deletePerson(_ id: UUID) {
        voices.delete(personID: id)
    }

    func deleteAllVoiceProfiles() {
        voices.deleteAll()
    }

    // MARK: - Storage location

    /// Lets the user pick the folder for new recordings.
    func chooseStorageFolder() {
        guard !recorder.isActive else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Auswählen")
        panel.message = String(localized: "Ordner für neue Aufnahmen wählen")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try library.locations.use(url) }
    }

    func useDefaultStorage() {
        guard !recorder.isActive else { return }
        library.locations.useDefault()
    }

    func revealInFinder(_ recording: Recording) {
        guard let url = library.audioURL(for: recording) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Selects a recording and widens filter and search so it is visible.
    func reveal(_ recording: Recording) {
        if let item = sidebarSelection, !item.matches(recording) {
            sidebarSelection = .all
        }
        if !recording.matches(searchText: searchText) {
            searchText = ""
        }
        selectedRecordingID = recording.id
    }

    func focusSearch() {
        searchFocusRequest += 1
    }
}
