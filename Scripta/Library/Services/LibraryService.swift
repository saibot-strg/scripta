import Foundation
import SwiftData
import os

/// Mutating operations on the library. Runs on the main actor because it
/// works with the container's `mainContext`, which also drives the UI.
@MainActor
final class LibraryService {
    let modelContext: ModelContext
    let locations: StorageLocations

    /// Storage for new recordings (the chosen location).
    var storage: RecordingStorage { locations.current }

    init(modelContext: ModelContext, locations: StorageLocations) {
        self.modelContext = modelContext
        self.locations = locations
    }

    /// Fixed storage, for tests and previews.
    convenience init(modelContext: ModelContext, storage: RecordingStorage = RecordingStorage()) {
        self.init(modelContext: modelContext, locations: StorageLocations(fixed: storage))
    }

    /// Where a recording's files are (its location at recording time).
    func storage(for recording: Recording) -> RecordingStorage {
        locations.storage(forBookmark: recording.storageRootBookmark)
    }

    /// Adds a finished recording whose audio files are already on disk, then
    /// removes its manifest. Meetings get their microphone and system tracks too.
    /// - Parameter rootBookmark: The storage location the files were written to.
    @discardableResult
    func addRecording(
        manifest: RecordingManifest,
        duration: TimeInterval,
        title: String? = nil,
        rootBookmark: Data? = nil
    ) throws(LibraryError) -> Recording {
        let storage = locations.storage(forBookmark: rootBookmark)
        let recording = Recording(
            id: manifest.id,
            title: title ?? manifest.title,
            createdAt: manifest.createdAt,
            duration: duration,
            source: manifest.source
        )
        recording.storageRootBookmark = rootBookmark
        modelContext.insert(recording)
        recording.tracks.append(AudioTrack(role: .primary, fileName: manifest.fileName, duration: duration))
        let separateTracks: [(TrackRole, String?)] = [(.microphone, manifest.microphoneFileName), (.system, manifest.systemFileName)]
        for case let (role, fileName?) in separateTracks {
            let url = storage.fileURL(for: manifest.id, fileName: fileName)
            recording.tracks.append(AudioTrack(role: role, fileName: fileName, duration: AudioFileInfo.duration(of: url) ?? duration))
        }
        try save()
        storage.removeManifest(for: manifest.id)
        return recording
    }

    func recording(withID id: UUID) -> Recording? {
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// URL of the playable audio file, if it exists on disk.
    func audioURL(for recording: Recording) -> URL? {
        audioURL(for: recording, role: .primary)
    }

    /// URL of a track's file, if it exists on disk.
    func audioURL(for recording: Recording, role: TrackRole) -> URL? {
        guard let track = recording.tracks.first(where: { $0.role == role }) else { return nil }
        let url = storage(for: recording).fileURL(for: recording.id, fileName: track.fileName)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Points a track to a new file (e.g. after AAC encoding) and deletes the old one.
    func replaceFile(of track: AudioTrack, in recording: Recording, with fileName: String) throws(LibraryError) {
        guard track.fileName != fileName else { return }
        let oldURL = storage(for: recording).fileURL(for: recording.id, fileName: track.fileName)
        track.fileName = fileName
        try save()
        try? FileManager.default.removeItem(at: oldURL)
    }

    /// Renames a recording. Empty titles are ignored.
    func rename(_ recording: Recording, to newTitle: String) throws(LibraryError) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != recording.title else { return }
        recording.title = title
        try save()
    }

    /// Deletes a recording and its transcript; its audio files go to the Trash.
    func delete(_ recording: Recording) throws(LibraryError) {
        let id = recording.id
        let title = recording.title
        let storage = storage(for: recording)
        modelContext.delete(recording)
        try save()
        // Files go last: if saving fails, the recording stays intact and playable.
        do {
            try storage.trashFolder(for: id, title: title)
        } catch {
            Logger.storage.error("Could not remove files of \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .fileRemovalFailed(underlying: error)
        }
    }

    // MARK: - Folders

    func transcript(withID id: UUID) -> Transcript? {
        var descriptor = FetchDescriptor<Transcript>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func segment(withID id: UUID) -> TranscriptSegment? {
        var descriptor = FetchDescriptor<TranscriptSegment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func folder(withID id: UUID) -> Folder? {
        let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    /// `id` brings back a folder that was deleted (undo).
    @discardableResult
    func createFolder(named name: String, id: UUID? = nil) throws(LibraryError) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(name: trimmed.isEmpty ? String(localized: "Neuer Ordner") : trimmed)
        if let id { folder.id = id }
        modelContext.insert(folder)
        try save()
        return folder
    }

    /// Empty names are ignored.
    func rename(_ folder: Folder, to newName: String) throws(LibraryError) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != folder.name else { return }
        folder.name = name
        try save()
    }

    /// Deletes the folder; its recordings stay in the library.
    func delete(_ folder: Folder) throws(LibraryError) {
        modelContext.delete(folder)
        try save()
    }

    /// Files recordings in a folder (nil takes them out of their folder).
    func move(_ recordings: [Recording], to folder: Folder?) throws(LibraryError) {
        for recording in recordings {
            recording.folder = folder
        }
        try save()
    }

    func save() throws(LibraryError) {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            Logger.library.error("Save failed: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
            throw .saveFailed(underlying: error)
        }
    }

    #if DEBUG
    /// Inserts dummy recordings for UI development.
    func insertSampleData() throws(LibraryError) {
        SampleData.insert(into: modelContext)
        try save()
    }

    /// Removes all recordings (debug builds only).
    func deleteAll() throws(LibraryError) {
        let recordings = (try? modelContext.fetch(FetchDescriptor<Recording>())) ?? []
        for recording in recordings {
            try delete(recording)
        }
    }
    #endif
}
