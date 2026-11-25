import Foundation
import os

/// A one-time copy of the library and the recordings in the app container,
/// made before the first launch with folders named after titles changes
/// anything (database schema 3, renamed and moved folders).
///
/// The copy lives in `Application Support/Sicherung vor Ordnernamen/`. On
/// APFS the audio is cloned, so it takes no extra space until the originals
/// are deleted. Existing recordings are only renamed once the copy exists.
enum LibraryBackup {
    static let doneKey = "backup.beforeNamedFolders"
    static let folderName = "Sicherung vor Ordnernamen"

    /// Makes the copy unless it was made before or there is no library yet.
    /// Must run before the library store is opened.
    /// - Returns: Whether the copy exists (or nothing needed one).
    @discardableResult
    static func makeIfNeeded(
        defaults: UserDefaults = .standard,
        supportURL: URL = .applicationSupportDirectory,
        recordingsURL: URL = RecordingStorage.defaultRootURL
    ) -> Bool {
        guard !defaults.bool(forKey: doneKey) else { return true }
        let fileManager = FileManager.default
        let store = supportURL.appending(path: "Library.store", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: store.path(percentEncoded: false)) else {
            // A new installation: nothing to keep.
            defaults.set(true, forKey: doneKey)
            return true
        }
        let backup = supportURL.appending(path: folderName, directoryHint: .isDirectory)
        do {
            // Left over from an attempt that failed halfway.
            if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
                try fileManager.removeItem(at: backup)
            }
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
            for name in ["Library.store", "Library.store-wal", "Library.store-shm"] {
                let source = supportURL.appending(path: name, directoryHint: .notDirectory)
                guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                try fileManager.copyItem(at: source, to: backup.appending(path: name, directoryHint: .notDirectory))
            }
            if fileManager.fileExists(atPath: recordingsURL.path(percentEncoded: false)) {
                try fileManager.copyItem(at: recordingsURL, to: backup.appending(path: "Recordings", directoryHint: .isDirectory))
            }
            defaults.set(true, forKey: doneKey)
            Logger.storage.notice("Backed up the library before naming folders after titles")
            return true
        } catch {
            Logger.storage.error("Backup before naming folders failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func isDone(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: doneKey)
    }
}
