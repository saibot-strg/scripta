import AppKit
import Foundation
import os

/// Titles and summaries written by a language model.
extension AppModel {
    // MARK: - Titles

    /// After a transcription: suggests a title if the setting is on and the
    /// recording still has the title Scripta gave it.
    func transcriptStored(recordingID id: UUID, isFirst: Bool) {
        guard let recording = library.recording(withID: id) else { return }
        let applies = automaticTitle.applies(to: recording, isFirstTranscript: isFirst)
        // Only needed until the first transcript exists.
        automaticTitle.forget(id)
        guard automaticTitle.isEnabled, applies, languageModels.titleModel != nil else { return }
        Task { await generateTitle(forRecordingID: id, automatic: true) }
    }

    /// "Titel erzeugen" in menus and the toolbar: replaces any title, undoable.
    func generateTitle(for recording: Recording) {
        let id = recording.id
        Task { await generateTitle(forRecordingID: id, automatic: false) }
    }

    func canGenerateTitle(for recording: Recording) -> Bool {
        recording.transcript.map { !$0.segments.isEmpty } == true
            && languageModels.titleModel != nil
            && !languageModels.titleJobs.contains(recording.id)
    }

    private func generateTitle(forRecordingID id: UUID, automatic: Bool) async {
        guard let recording = library.recording(withID: id) else { return }
        guard let transcript = recording.transcript, !transcript.segments.isEmpty else {
            if !automatic { presentedError = PresentableError(LanguageModelError.noTranscript) }
            return
        }
        let previous = recording.title
        do {
            let title = try await languageModels.suggestTitle(for: id, transcript: TranscriptText(transcript, namesSpeakers: false))
            guard let recording = library.recording(withID: id) else { return }
            // Renamed by the user while the model was writing: keep their title.
            if automatic, recording.title != previous { return }
            setTitle(title, of: recording, actionName: String(localized: "Titel erzeugen"))
            if !automatic { showToast(String(localized: "Titel erzeugt")) }
        } catch is CancellationError {
            return
        } catch {
            Logger.languageModels.error("Title failed: \(error.localizedDescription, privacy: .public)")
            if !automatic { presentedError = PresentableError(error) }
        }
    }

    /// Sets a title as one undo step; undoing sets the previous one again.
    private func setTitle(_ title: String, of recording: Recording, actionName: String) {
        let previous = recording.title
        perform { try library.rename(recording, to: title) }
        guard recording.title != previous else { return }
        let id = recording.id
        undo.register(actionName) { [weak self] in
            guard let self, let recording = library.recording(withID: id) else { return }
            setTitle(previous, of: recording, actionName: actionName)
        }
    }

    // MARK: - Summaries

    /// The recording's folder, where `summary.json` lives (nil if its location can't be reached).
    func summaryFolder(for recording: Recording) -> URL? {
        library.folderURL(for: recording)
    }

    func summary(for recording: Recording) -> TranscriptSummary? {
        summaryFolder(for: recording).flatMap { languageModels.summary(for: recording.id, in: $0) }
    }

    func summarize(_ recording: Recording) {
        guard let transcript = recording.transcript, !transcript.segments.isEmpty else {
            presentedError = PresentableError(LanguageModelError.noTranscript)
            return
        }
        let id = recording.id
        let text = TranscriptText(transcript, namesSpeakers: true)
        let modifiedAt = transcript.modifiedAt
        // Looked up when the summary is saved: the title, and with it the folder, may change meanwhile.
        let folder = { @MainActor [weak self] () -> URL? in
            guard let self, let recording = library.recording(withID: id) else { return nil }
            return summaryFolder(for: recording)
        }
        Task {
            do {
                try await languageModels.summarize(recordingID: id, transcript: text, transcriptModifiedAt: modifiedAt, folder: folder)
            } catch is CancellationError {
                return
            } catch {
                Logger.languageModels.error("Summary failed: \(error.localizedDescription, privacy: .public)")
                presentedError = PresentableError(error)
            }
        }
    }

    func cancelSummary(of recording: Recording) {
        languageModels.cancelSummary(for: recording.id)
    }

    func copySummary(of recording: Recording) {
        guard let summary = summary(for: recording) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.text, forType: .string)
        showToast(String(localized: "Zusammenfassung kopiert"))
    }
}
