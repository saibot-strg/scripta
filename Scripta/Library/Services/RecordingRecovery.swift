import Foundation
import os

/// Adds recordings to the library that were interrupted by a crash or a forced
/// quit. Runs once at launch, before any new recording starts.
@MainActor
struct RecordingRecovery {
    let library: LibraryService

    /// Returns the number of recovered recordings.
    /// - Parameter activeRecordingID: The recording in progress right now, if
    ///   any; its manifest is expected and must not be recovered.
    @discardableResult
    func recoverInterruptedRecordings(activeRecordingID: () -> UUID? = { nil }) async -> Int {
        let storage = library.storage
        var recovered = 0
        for folder in storage.recordingFolders() {
            guard let manifest = storage.readManifest(in: folder),
                  manifest.id != activeRecordingID() else { continue }

            // Saved to the library, but the app quit before the manifest was removed.
            if library.recording(withID: manifest.id) != nil {
                storage.removeManifest(for: manifest.id)
                continue
            }

            guard let duration = await recoverableDuration(of: manifest), duration > 0 else {
                // Nothing usable was written.
                Logger.storage.info("Discarding empty interrupted recording \(manifest.id, privacy: .public)")
                try? storage.removeFolder(for: manifest.id)
                continue
            }

            do {
                let title = String(localized: "\(manifest.title) (wiederhergestellt)")
                try library.addRecording(manifest: manifest, duration: duration, title: title)
                recovered += 1
                Logger.storage.notice("Recovered interrupted recording \(manifest.id, privacy: .public)")
            } catch {
                Logger.storage.error("Recovery failed for \(manifest.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return recovered
    }

    /// Duration of the playable file; meetings get their tracks mixed first.
    private func recoverableDuration(of manifest: RecordingManifest) async -> TimeInterval? {
        let storage = library.storage
        guard manifest.isMeeting else {
            return AudioFileInfo.duration(of: storage.fileURL(for: manifest.id, fileName: manifest.fileName))
        }
        let hasAudio = manifest.capturedFileNames.contains { name in
            (AudioFileInfo.duration(of: storage.fileURL(for: manifest.id, fileName: name)) ?? 0) > 0
        }
        guard hasAudio else { return nil }
        return try? await MeetingFinisher.mixTracks(of: manifest, storage: storage)
    }
}
