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
    let dictation: DictationController
    let player = PlayerModel()

    var sidebarSelection: LibraryFilter? = .all
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
    private var encodingIDs: Set<UUID> = []

    init(library: LibraryService) {
        self.library = library
        recorder = AudioRecorder(location: { [library] in
            RecordingLocation(storage: library.storage, bookmark: library.locations.currentBookmark)
        })
        transcription = TranscriptionService(library: library)
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
    func importFiles(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        Task { await performImport(files) }
    }

    private func performImport(_ urls: [URL]) async {
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
    func rename(_ speaker: SpeakerLabel, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speaker.customName = trimmed.isEmpty || trimmed == speaker.defaultName ? nil : trimmed
        speaker.transcript?.rebuildFullText()
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

    func transcribe(_ recording: Recording) {
        transcription.enqueue(recording)
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

    /// Mixing a meeting's tracks after it stopped.
    private(set) var isSavingRecording = false
    /// Apps that can be recorded on their own in a meeting.
    private(set) var meetingApps: [MeetingApp] = []

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
        meetingApps = AudioAppCatalog.availableApps()
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

    /// Stops recording and adds the recording to the library. Meetings are
    /// mixed in the background first.
    func stopRecording() {
        guard let finished = recorder.stop() else { return }
        guard finished.manifest.isMeeting else {
            addToLibrary(finished.manifest, duration: finished.duration, rootBookmark: finished.rootBookmark)
            return
        }
        isSavingRecording = true
        Task {
            defer { isSavingRecording = false }
            do {
                let duration = try await MeetingFinisher.mixTracks(of: finished.manifest, storage: finished.storage)
                addToLibrary(finished.manifest, duration: duration, rootBookmark: finished.rootBookmark)
            } catch {
                // The manifest stays on disk, so the meeting is recovered on next launch.
                Logger.recording.error("Mixing failed: \(error.localizedDescription, privacy: .public)")
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
        perform { try library.delete(recording) }
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
        if let filter = sidebarSelection, !filter.matches(recording) {
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
