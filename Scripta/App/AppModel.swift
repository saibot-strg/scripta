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
    /// ⌘Z for the user's own edits (see `UndoCoordinator`).
    let undo: UndoCoordinator
    /// Asked before the first meeting recording.
    var meetingNotice = MeetingNotice()

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
    /// A recording with corrections the user asked to transcribe again; the
    /// main window asks first, because the corrections would be lost.
    var retranscriptionRequest: Recording?

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
        undo = UndoCoordinator()
        transcription.onTranscriptReplaced = { [weak self] in self?.undo.clear() }
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
        setText(of: segment, to: trimmed, original: segment.originalText ?? segment.text, actionName: String(localized: "Text bearbeiten"))
    }

    func restoreOriginalText(of segment: TranscriptSegment) {
        guard let original = segment.originalText else { return }
        setText(of: segment, to: original, original: nil, actionName: String(localized: "Originaltext wiederherstellen"))
    }

    /// Sets a segment's text and engine text; undo sets the previous pair.
    private func setText(of segment: TranscriptSegment, to text: String, original: String?, actionName: String) {
        let previous = (text: segment.text, original: segment.originalText)
        let id = segment.id
        segment.text = text
        segment.originalText = original
        segment.transcript?.rebuildFullText()
        perform { try library.save() }
        undo.register(actionName) { [weak self] in
            guard let self, let segment = library.segment(withID: id) else { return }
            setText(of: segment, to: previous.text, original: previous.original, actionName: actionName)
        }
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
        changeSpeakers(of: transcript, actionName: String(localized: "Sprecher umbenennen")) {
            setName(trimmed, of: speaker, remember: remember)
        }
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
        guard !assignments.isEmpty else { return }
        changeSpeakers(of: transcript, actionName: String(localized: "Namen zuordnen")) {
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
                    mergeSpeaker(speaker, into: target, in: transcript)
                    merged.insert(speaker.id)
                } else {
                    survivors[name] = speaker
                }
            }
            for assignment in assignments where !merged.contains(assignment.speaker.id) {
                setName(assignment.name.trimmingCharacters(in: .whitespacesAndNewlines), of: assignment.speaker, remember: assignment.remember)
            }
        }
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
        changeSpeakers(of: transcript, actionName: String(localized: "Sprecher zusammenführen")) {
            mergeSpeaker(speaker, into: target, in: transcript)
        }
    }

    private func mergeSpeaker(_ speaker: SpeakerLabel, into target: SpeakerLabel, in transcript: Transcript) {
        voices.merge(labelID: speaker.id, into: target.id)
        for segment in Array(speaker.segments) {
            segment.speaker = target
        }
        transcript.speakers.removeAll { $0.id == speaker.id }
        library.modelContext.delete(speaker)
    }

    /// Runs a change to a transcript's speakers (names, merges, moved
    /// passages) as one undo step that restores the speakers as they were.
    private func changeSpeakers(of transcript: Transcript, actionName: String, _ change: () -> Void) {
        let before = SpeakerSnapshot(transcript, voices: voices)
        change()
        transcript.rebuildFullText()
        perform { try library.save() }
        registerRestore(of: before, actionName: actionName)
    }

    private func registerRestore(of snapshot: SpeakerSnapshot, actionName: String) {
        undo.register(actionName) { [weak self] in
            guard let self, let transcript = library.transcript(withID: snapshot.transcriptID) else { return }
            let current = SpeakerSnapshot(transcript, voices: voices)
            snapshot.restore(into: transcript, context: library.modelContext, voices: voices)
            transcript.rebuildFullText()
            perform { try library.save() }
            registerRestore(of: current, actionName: actionName)
        }
    }

    // MARK: - Export

    /// Short confirmation at the bottom of the window ("Transkript kopiert").
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    func showToast(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
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

    /// "Transkribieren" from a button or menu: asks first (in the main
    /// window) when a new transcript would discard the user's corrections.
    func requestTranscription(of recording: Recording) {
        if recording.transcript?.hasManualChanges == true {
            retranscriptionRequest = recording
        } else {
            transcribe(recording)
        }
    }

    /// Queues every recording without a transcript (batch transcription).
    func transcribeAllPending() {
        let all = (try? library.modelContext.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let pending = all.filter {
            ($0.status == .notTranscribed || $0.status == .failed) && library.audioURL(for: $0) != nil
        }
        for recording in pending {
            transcription.enqueue(recording)
        }
        showToast(pending.isEmpty
                  ? String(localized: "Keine Aufnahmen zum Transkribieren")
                  : String(localized: "\(pending.count) Aufnahmen in der Warteschlange"))
    }

    func cancelTranscription(of recording: Recording) {
        transcription.cancel(recording)
    }

    // MARK: - Recording

    /// Stopped recordings whose files are still being finished (levelling,
    /// mixing) before they are added to the library.
    private(set) var savingRecordings: [LiveRecording] = []
    var isSavingRecording: Bool { !savingRecordings.isEmpty }

    /// The running recording and the ones being saved, newest first, for
    /// the top of the recording list.
    var liveRecordings: [LiveRecording] {
        var items = savingRecordings.reversed() as [LiveRecording]
        if let id = recorder.activeRecordingID {
            items.insert(LiveRecording(id: id, title: recorder.title, source: recorder.isMeeting ? .meeting : .microphone), at: 0)
        }
        return items
    }
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
        #if DEBUG
        let asksFirst = !recorder.usesTestTone
        #else
        let asksFirst = true
        #endif
        if asksFirst, await !meetingNotice.confirm() { return }
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
        let manifest = finished.manifest
        savingRecordings.append(LiveRecording(id: manifest.id, title: manifest.title, source: manifest.source, isSaving: true))
        return Task {
            defer {
                savingRecordings.removeAll { $0.id == manifest.id }
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
        let previous = recording.title
        perform { try library.rename(recording, to: title) }
        guard recording.title != previous else { return }
        let id = recording.id
        undo.register(String(localized: "Aufnahme umbenennen")) { [weak self] in
            guard let self, let recording = library.recording(withID: id) else { return }
            rename(recording, to: previous)
        }
    }

    /// Deletes a recording; its audio files go to the Trash. Not undoable,
    /// so older undo steps (which may point into it) are dropped.
    func delete(_ recording: Recording) {
        if selectedRecordingID == recording.id {
            selectedRecordingID = nil
        }
        transcription.cancel(recording)
        voices.forgetRecording(recording.id)
        perform { try library.delete(recording) }
        undo.clear()
    }

    /// Moves one passage to another speaker of the same transcript: the
    /// diarization put two people into one voice. The source speaker's voice
    /// is then a mix and no longer teaches anyone's profile. A speaker left
    /// without passages is removed.
    func move(_ segment: TranscriptSegment, to target: SpeakerLabel) {
        guard let source = segment.speaker, source.id != target.id,
              let transcript = segment.transcript, target.transcript?.id == transcript.id else { return }
        changeSpeakers(of: transcript, actionName: String(localized: "Abschnitt verschieben")) {
            moveSegment(segment, from: source, to: target, in: transcript)
        }
    }

    /// Moves one passage to a new numbered speaker ("Sprecher 4"), named
    /// `name` if given (a known person not yet in this transcript). If a
    /// speaker already has that name, the passage goes there.
    func moveToNewSpeaker(_ segment: TranscriptSegment, named name: String? = nil) {
        guard let transcript = segment.transcript, let source = segment.speaker else { return }
        if let name, let existing = transcript.speakers.first(where: { $0.displayName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            move(segment, to: existing)
            return
        }
        changeSpeakers(of: transcript, actionName: String(localized: "Abschnitt verschieben")) {
            let number = (transcript.speakers.filter { $0.role == .diarized }.map(\.number).max() ?? 0) + 1
            let label = SpeakerLabel(role: .diarized, number: number, customName: name)
            transcript.speakers.append(label)
            moveSegment(segment, from: source, to: label, in: transcript)
        }
    }

    private func moveSegment(_ segment: TranscriptSegment, from source: SpeakerLabel, to target: SpeakerLabel, in transcript: Transcript) {
        let sourceKeepsPassages = source.segments.contains { $0.id != segment.id }
        voices.discardVoice(labelID: source.id)
        segment.speaker = target
        if !sourceKeepsPassages {
            transcript.speakers.removeAll { $0.id == source.id }
            library.modelContext.delete(source)
        }
    }

    // MARK: - Folders

    func createFolder(named name: String) {
        perform {
            let folder = try library.createFolder(named: name)
            sidebarSelection = .folder(folder.id)
            let id = folder.id
            undo.register(String(localized: "Neuer Ordner")) { [weak self] in
                self?.removeFolder(id: id, actionName: String(localized: "Neuer Ordner"))
            }
        }
    }

    func rename(_ folder: Folder, to name: String) {
        let previous = folder.name
        perform { try library.rename(folder, to: name) }
        guard folder.name != previous else { return }
        let id = folder.id
        undo.register(String(localized: "Ordner umbenennen")) { [weak self] in
            guard let self, let folder = library.folder(withID: id) else { return }
            rename(folder, to: previous)
        }
    }

    func delete(_ folder: Folder) {
        removeFolder(id: folder.id, actionName: String(localized: "Ordner löschen"))
    }

    /// Deletes a folder (its recordings stay); undo brings it back with the
    /// same recordings in it.
    private func removeFolder(id: UUID, actionName: String) {
        guard let folder = library.folder(withID: id) else { return }
        let name = folder.name
        let members = folder.recordings.map(\.id)
        if sidebarSelection == .folder(id) { sidebarSelection = .all }
        perform { try library.delete(folder) }
        undo.register(actionName) { [weak self] in
            self?.recreateFolder(id: id, name: name, recordingIDs: members, actionName: actionName)
        }
    }

    private func recreateFolder(id: UUID, name: String, recordingIDs: [UUID], actionName: String) {
        perform {
            let folder = try library.createFolder(named: name, id: id)
            try library.move(recordingIDs.compactMap(library.recording(withID:)), to: folder)
        }
        undo.register(actionName) { [weak self] in
            self?.removeFolder(id: id, actionName: actionName)
        }
    }

    /// Files recordings by ID (drag and drop) in a folder, nil = out of any folder.
    func move(recordingIDs: [UUID], to folder: Folder?) {
        moveRecordings(recordingIDs, toFolderID: folder?.id, actionName: String(localized: "In Ordner verschieben"))
    }

    private func moveRecordings(_ ids: [UUID], toFolderID folderID: UUID?, actionName: String) {
        let recordings = ids.compactMap(library.recording(withID:))
        let folder = folderID.flatMap(library.folder(withID:))
        guard !recordings.isEmpty, folderID == nil || folder != nil else { return }
        let previous = Dictionary(grouping: recordings) { $0.folder?.id }.mapValues { $0.map(\.id) }
        perform { try library.move(recordings, to: folder) }
        undo.register(actionName) { [weak self] in
            for (folderID, ids) in previous {
                self?.moveRecordings(ids, toFolderID: folderID, actionName: actionName)
            }
        }
    }

    // MARK: - People

    /// Renames a known person and every speaker named after them.
    func renamePerson(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let previous = voices.people.first(where: { $0.id == id })?.name, previous != trimmed else { return }
        var transcripts: [UUID: Transcript] = [:]
        for labelID in voices.rename(personID: id, to: trimmed) {
            let descriptor = FetchDescriptor<SpeakerLabel>(predicate: #Predicate { $0.id == labelID })
            guard let label = try? library.modelContext.fetch(descriptor).first else { continue }
            label.customName = trimmed
            if let transcript = label.transcript { transcripts[transcript.id] = transcript }
        }
        for transcript in transcripts.values { transcript.rebuildFullText() }
        perform { try library.save() }
        undo.register(String(localized: "Person umbenennen")) { [weak self] in
            self?.renamePerson(id, to: previous)
        }
    }

    /// Voice profiles are biometric data: deleting them is final, also for undo.
    func deletePerson(_ id: UUID) {
        voices.delete(personID: id)
        undo.clear()
    }

    func deleteAllVoiceProfiles() {
        voices.deleteAll()
        undo.clear()
    }

    // MARK: - Undo

    /// Undo steps go to the main window's undo manager (Edit menu).
    func attachUndoManager(_ manager: UndoManager?) {
        undo.attach(manager)
    }

    // MARK: - Language

    /// Whether quitting now would interrupt something (recording, saving).
    var canRelaunch: Bool {
        !recorder.isActive && !isSavingRecording
    }

    /// Starts a new instance of Scripta, then quits this one: the language
    /// setting only applies at launch.
    func relaunch() {
        guard canRelaunch else { return }
        // Frees the dictation shortcut for the new instance.
        dictation.setShortcutSuspended(true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.dictation.setShortcutSuspended(false)
                    self?.presentedError = PresentableError(error)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
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
